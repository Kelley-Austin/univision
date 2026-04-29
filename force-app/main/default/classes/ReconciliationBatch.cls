/**
 * Batch Apex that reconciles Budget Lines (planned advertising spend) against
 * Counterpoint actuals (Actuals_Record__c records ingested from Counterpoint CSV exports).
 *
 * Match key: Channel/Station + Vehicle + Month + Fiscal Year.
 * For each Budget Line the batch:
 *   1. Sums Net_Revenue__c from all Actuals_Record__c records sharing the same key.
 *   2. Writes the total to Budget_Line__c.Actual_Amount__c so the formula fields
 *      Variance_Amount__c and Variance_Status__c auto-update.
 *   3. Links matched actuals to their Advertising_Contract__c via the opportunity chain.
 *   4. Upserts a Reconciliation_Line__c record (keyed on Match_Key__c) with the
 *      status Matched, Variance, or Unmatched Order.
 * After all Budget Lines are processed, finish() creates Unmatched Actual
 * Reconciliation_Line__c records for any actuals group that had no Budget Line.
 *
 * Usage:
 *   Database.executeBatch(new ReconciliationBatch(), 200);                 // all records
 *   Database.executeBatch(new ReconciliationBatch(opportunityId), 200);    // one opportunity
 */
public class ReconciliationBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ─── Month number → name lookup ───────────────────────────────────────────
    @TestVisible
    private static final Map<Integer, String> MONTH_NAMES = new Map<Integer, String>{
        1 => 'January',   2 => 'February', 3 => 'March',    4 => 'April',
        5 => 'May',       6 => 'June',     7 => 'July',     8 => 'August',
        9 => 'September', 10 => 'October', 11 => 'November', 12 => 'December'
    };

    private Id opportunityId;

    // Populated in start(), read across all execute() calls — requires Database.Stateful
    @TestVisible private Map<String, ActualAggregate> actualsMap;
    @TestVisible private Set<String>                  matchedKeys;

    // ─── Inner class ─────────────────────────────────────────────────────────
    private class ActualAggregate {
        Decimal totalNet  = 0;
        Integer spotCount = 0;
        Id      sampleActualId;   // one actual ID for contract linkage
        Id      channelId;
        Id      vehicleId;
        String  monthName;
        String  fiscalYear;
    }

    // ─── Constructors ─────────────────────────────────────────────────────────
    public ReconciliationBatch() {}

    public ReconciliationBatch(Id opportunityId) {
        this.opportunityId = opportunityId;
    }

    // ─── Batchable ────────────────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        actualsMap  = new Map<String, ActualAggregate>();
        matchedKeys = new Set<String>();

        // Load all Actuals_Record__c that have resolved Station and Vehicle lookups.
        // We aggregate by (Station + Vehicle + Month + FiscalYear) so that multiple
        // spot-level actuals roll up to the monthly Budget Line grain.
        for (Actuals_Record__c ar : [
            SELECT Id, Station__c, Vehicle__c,
                   Calendar_Date__c, Broadcast_Date__c, Date_Type__c,
                   Net_Revenue__c, Advertising_Contract__c
            FROM   Actuals_Record__c
            WHERE  Station__c != null
            AND    Vehicle__c  != null
        ]) {
            Date effectiveDate = ar.Date_Type__c == 'Broadcast'
                ? ar.Broadcast_Date__c
                : ar.Calendar_Date__c;
            if (effectiveDate == null) continue;

            String monthName  = MONTH_NAMES.get(effectiveDate.month());
            String fiscalYear = String.valueOf(effectiveDate.year());
            String key        = buildKey(ar.Station__c, ar.Vehicle__c, monthName, fiscalYear);

            if (!actualsMap.containsKey(key)) {
                ActualAggregate agg = new ActualAggregate();
                agg.sampleActualId = ar.Id;
                agg.channelId      = ar.Station__c;
                agg.vehicleId      = ar.Vehicle__c;
                agg.monthName      = monthName;
                agg.fiscalYear     = fiscalYear;
                actualsMap.put(key, agg);
            }

            ActualAggregate agg = actualsMap.get(key);
            agg.totalNet  += ar.Net_Revenue__c != null ? ar.Net_Revenue__c : 0;
            agg.spotCount++;
        }

        if (opportunityId != null) {
            return Database.getQueryLocator([
                SELECT Id, Advertising_Opportunity__c, Channel__c, Vehicle__c,
                       Month__c, Fiscal_Year__c, Planned_Amount__c, Weekly_Spots__c
                FROM   Budget_Line__c
                WHERE  Advertising_Opportunity__c = :opportunityId
                AND    Status__c != 'Cancelled'
            ]);
        } else {
            return Database.getQueryLocator([
                SELECT Id, Advertising_Opportunity__c, Channel__c, Vehicle__c,
                       Month__c, Fiscal_Year__c, Planned_Amount__c, Weekly_Spots__c
                FROM   Budget_Line__c
                WHERE  Status__c != 'Cancelled'
            ]);
        }
    }

    public void execute(Database.BatchableContext bc, List<Budget_Line__c> scope) {
        // ── Resolve opportunity → contract mapping for this chunk ────────────
        Set<Id> oppIds = new Set<Id>();
        for (Budget_Line__c bl : scope) {
            if (bl.Advertising_Opportunity__c != null) oppIds.add(bl.Advertising_Opportunity__c);
        }

        Map<Id, Id> oppToContract = new Map<Id, Id>();
        for (Advertising_Contract__c c : [
            SELECT Id, Advertising_Opportunity__c
            FROM   Advertising_Contract__c
            WHERE  Advertising_Opportunity__c IN :oppIds
        ]) {
            // First contract wins when an opportunity has multiple
            if (!oppToContract.containsKey(c.Advertising_Opportunity__c)) {
                oppToContract.put(c.Advertising_Opportunity__c, c.Id);
            }
        }

        // ── Build reconciliation lines ────────────────────────────────────────
        List<Reconciliation_Line__c> recLines   = new List<Reconciliation_Line__c>();
        List<Budget_Line__c>         blUpdates  = new List<Budget_Line__c>();
        Map<Id, Id>                  arContractMap = new Map<Id, Id>();

        for (Budget_Line__c bl : scope) {
            // Skip lines missing the key dimensions needed for a match
            if (bl.Channel__c == null || bl.Vehicle__c == null
                    || String.isBlank(bl.Month__c) || String.isBlank(bl.Fiscal_Year__c)) {
                continue;
            }

            String key = buildKey(bl.Channel__c, bl.Vehicle__c, bl.Month__c, bl.Fiscal_Year__c);
            ActualAggregate agg = actualsMap.get(key);

            Reconciliation_Line__c rec = new Reconciliation_Line__c();
            rec.Budget_Line__c           = bl.Id;
            rec.Advertising_Opportunity__c = bl.Advertising_Opportunity__c;
            rec.Channel__c               = bl.Channel__c;
            rec.Vehicle__c               = bl.Vehicle__c;
            rec.Month__c                 = bl.Month__c;
            rec.Fiscal_Year__c           = bl.Fiscal_Year__c;
            rec.Planned_Amount__c        = bl.Planned_Amount__c;
            rec.Planned_Weekly_Spots__c  = bl.Weekly_Spots__c != null ? (Integer) bl.Weekly_Spots__c : 0;
            rec.Match_Key__c             = 'BL|' + bl.Id;

            Decimal actualAmt = 0;
            Integer spotCount = 0;

            if (agg != null) {
                actualAmt = agg.totalNet;
                spotCount = agg.spotCount;

                Decimal planned = bl.Planned_Amount__c != null ? bl.Planned_Amount__c : 0;
                rec.Reconciliation_Status__c = (actualAmt == planned) ? 'Matched' : 'Variance';

                // Link actuals to the contract resolved from the budget line's opportunity
                Id contractId = oppToContract.get(bl.Advertising_Opportunity__c);
                if (contractId != null && agg.sampleActualId != null) {
                    arContractMap.put(agg.sampleActualId, contractId);
                }
                matchedKeys.add(key);
            } else {
                rec.Reconciliation_Status__c = 'Unmatched Order';
            }

            rec.Actual_Amount__c    = actualAmt;
            rec.Actual_Spot_Count__c = spotCount;
            recLines.add(rec);

            // Null clears a stale Actual_Amount__c from a previous run
            blUpdates.add(new Budget_Line__c(
                Id = bl.Id,
                Actual_Amount__c = agg != null ? actualAmt : null
            ));
        }

        // ── Persist ───────────────────────────────────────────────────────────
        if (!recLines.isEmpty())  upsert recLines Reconciliation_Line__c.Match_Key__c;
        if (!blUpdates.isEmpty()) update blUpdates;

        if (!arContractMap.isEmpty()) {
            List<Actuals_Record__c> arUpdates = new List<Actuals_Record__c>();
            for (Id arId : arContractMap.keySet()) {
                arUpdates.add(new Actuals_Record__c(
                    Id = arId,
                    Advertising_Contract__c = arContractMap.get(arId)
                ));
            }
            update arUpdates;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Create Unmatched Actual rows for every actuals aggregate that had no Budget Line
        List<Reconciliation_Line__c> unmatched = new List<Reconciliation_Line__c>();

        for (String key : actualsMap.keySet()) {
            if (matchedKeys.contains(key)) continue;

            ActualAggregate agg = actualsMap.get(key);
            Reconciliation_Line__c rec = new Reconciliation_Line__c();
            rec.Channel__c               = agg.channelId;
            rec.Vehicle__c               = agg.vehicleId;
            rec.Month__c                 = agg.monthName;
            rec.Fiscal_Year__c           = agg.fiscalYear;
            rec.Actual_Amount__c         = agg.totalNet;
            rec.Actual_Spot_Count__c     = agg.spotCount;
            rec.Planned_Amount__c        = 0;
            rec.Planned_Weekly_Spots__c  = 0;
            rec.Reconciliation_Status__c = 'Unmatched Actual';
            // Stable key so re-runs overwrite rather than duplicate
            rec.Match_Key__c = 'ACT|' + agg.channelId + '|' + agg.vehicleId
                             + '|' + agg.monthName + '|' + agg.fiscalYear;
            unmatched.add(rec);
        }

        if (!unmatched.isEmpty()) upsert unmatched Reconciliation_Line__c.Match_Key__c;
    }

    // ─── Private helpers ─────────────────────────────────────────────────────

    @TestVisible
    private static String buildKey(Id channelId, Id vehicleId, String month, String fiscalYear) {
        return String.valueOf(channelId) + '|'
             + String.valueOf(vehicleId) + '|'
             + (month      != null ? month      : '') + '|'
             + (fiscalYear != null ? fiscalYear : '');
    }
}
