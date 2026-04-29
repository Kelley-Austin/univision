/**
 * Core reconciliation orchestrator.
 *
 * reconcileBatch() takes a chunk of Pending Inbound_Staging__c rows and:
 *  1. Resolves each row to an Account via AccountMatcher (3 tiers).
 *  2. Resolves each row to a User via SalespersonMatcher (5 tiers).
 *  3. For fully-matched rows (Tier 1 or 2 account match): upserts Actual_Revenue__c
 *     on External_Key__c and marks the staging row Matched.
 *  4. For unmatched rows: marks the staging row Unmatched (surfaced in worklist).
 *  5. Enqueues ProjectionRollupQueueable with the newly upserted Actual_Revenue__c IDs.
 *
 * Called by ReconciliationBatch per chunk.
 */
public with sharing class ReconciliationEngine {

    // ── Public types ──────────────────────────────────────────────────────────

    public class ReconcileResult {
        public Integer matched   = 0;
        public Integer unmatched = 0;
        public Integer excluded  = 0;
        public Integer errors    = 0;
    }

    // ── Entry point ───────────────────────────────────────────────────────────

    public static ReconcileResult reconcileBatch(
        List<Inbound_Staging__c> rows,
        String sourceSystemCode
    ) {
        ReconcileResult result = new ReconcileResult();
        if (rows == null || rows.isEmpty()) return result;

        // ── Run matchers ──────────────────────────────────────────────────────
        List<AccountMatcher.MatchResult>       accountResults = AccountMatcher.matchBulk(rows);
        Set<String> rawCodes = new Set<String>();
        for (Inbound_Staging__c row : rows) {
            if (String.isNotBlank(row.Raw_Salesperson_Code__c)) {
                rawCodes.add(row.Raw_Salesperson_Code__c.trim());
            }
        }
        Map<String, SalespersonMatcher.AEMatchResult> aeResults =
            SalespersonMatcher.matchBulk(rawCodes, sourceSystemCode);

        // ── Build Actual_Revenue__c upsert list ───────────────────────────────
        List<Actual_Revenue__c> actualsToUpsert = new List<Actual_Revenue__c>();
        List<Inbound_Staging__c> stagingToUpdate = new List<Inbound_Staging__c>();

        for (Integer i = 0; i < rows.size(); i++) {
            Inbound_Staging__c row = rows[i];
            AccountMatcher.MatchResult accMatch = accountResults[i];
            String rawAe = String.isNotBlank(row.Raw_Salesperson_Code__c)
                ? row.Raw_Salesperson_Code__c.trim() : null;
            SalespersonMatcher.AEMatchResult aeMatch = (rawAe != null && aeResults.containsKey(rawAe))
                ? aeResults.get(rawAe) : null;

            // Stamp match tiers on staging row
            row.Match_Account_Tier__c = accMatch.tier;
            row.Match_AE_Tier__c      = aeMatch != null ? aeMatch.tier : null;
            row.Account__c            = accMatch.accountId;
            row.AE_User__c            = aeMatch != null ? aeMatch.userId : null;

            if (accMatch.tier <= 2 && accMatch.accountId != null) {
                // Matched — build Actual_Revenue__c
                row.Status__c = 'Matched';
                result.matched++;
                actualsToUpsert.add(buildActual(row, accMatch.accountId));
            } else {
                // Unmatched — surface in worklist
                row.Status__c = 'Unmatched';
                result.unmatched++;
            }
            stagingToUpdate.add(row);
        }

        // ── Upsert actuals ────────────────────────────────────────────────────
        Set<Id> upsertedActualIds = new Set<Id>();
        if (!actualsToUpsert.isEmpty()) {
            Database.UpsertResult[] uResults =
                Database.upsert(actualsToUpsert, Actual_Revenue__c.External_Key__c, false);
            for (Integer i = 0; i < uResults.size(); i++) {
                if (uResults[i].isSuccess()) {
                    upsertedActualIds.add(uResults[i].getId());
                } else {
                    // Mark staging row back to Error if actual upsert failed
                    stagingToUpdate[i].Status__c      = 'Error';
                    stagingToUpdate[i].Excluding_Rule__c =
                        uResults[i].getErrors()[0].getMessage().abbreviate(255);
                    result.matched--;
                    result.errors++;
                }
            }
        }

        // ── Update staging rows ───────────────────────────────────────────────
        update stagingToUpdate;

        // ── Enqueue projection rollup ─────────────────────────────────────────
        if (!upsertedActualIds.isEmpty()) {
            System.enqueueJob(new ProjectionRollupQueueable(upsertedActualIds));
        }

        return result;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Actual_Revenue__c buildActual(Inbound_Staging__c row, Id accountId) {
        // External_Key__c = same dedup key already on staging row
        Actual_Revenue__c a = new Actual_Revenue__c();
        a.External_Key__c    = row.External_Key__c;
        a.Account__c         = accountId;
        a.Revenue_Amount__c  = row.Revenue_Amount__c;
        a.Revenue_Type__c    = row.Revenue_Type__c;
        a.Period_Month__c    = row.Period_Month__c;
        a.Period_Year__c     = row.Period_Year__c;
        a.Station_Code__c    = row.Station_Code__c;
        a.AE_Code__c         = row.Raw_Salesperson_Code__c;
        a.Broadcast_Period__c = row.Broadcast_Period__c;
        a.Source_System__c   = row.Source_System__c;
        a.Inbound_Staging__c = row.Id;
        return a;
    }
}
