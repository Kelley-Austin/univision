/**
 * AuraEnabled controller backing the lateActualsWorklist LWC.
 *
 * Surfaces Actual_Revenue__c records where Is_Late__c = true and
 * Late_Disposition__c = 'Pending' (or null). Operations:
 *   getLateActuals  — paginated list with total count
 *   acceptLateActual — sets Late_Disposition__c = Accepted; row stays in rollup
 *   rejectLateActual — sets Late_Disposition__c = Rejected; row is excluded from rollup
 *   bulkDispose      — accept or reject multiple rows in one call
 */
public with sharing class LateActualsController {

    // ── Data transfer object ──────────────────────────────────────────────────

    public class LateActualRow {
        @AuraEnabled public Id      actualId;
        @AuraEnabled public String  advertiserName;
        @AuraEnabled public String  aeCode;
        @AuraEnabled public Decimal revenueAmount;
        @AuraEnabled public Integer periodMonth;
        @AuraEnabled public Integer periodYear;
        @AuraEnabled public String  revenueType;
        @AuraEnabled public String  sourceSystem;
        @AuraEnabled public String  stationCode;
        @AuraEnabled public String  disposition;
    }

    public class LateActualResult {
        @AuraEnabled public List<LateActualRow> rows;
        @AuraEnabled public Integer             totalCount;
    }

    // ── Paginated list ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static LateActualResult getLateActuals(Integer pageSize, Integer pageOffset) {
        Integer size   = pageSize   != null ? pageSize   : 50;
        Integer offset = pageOffset != null ? pageOffset : 0;

        Integer total = [
            SELECT COUNT()
            FROM   Actual_Revenue__c
            WHERE  Is_Late__c = true
              AND  (Late_Disposition__c = null OR Late_Disposition__c = 'Pending')
        ];

        List<Actual_Revenue__c> actuals = [
            SELECT Id, Advertiser__r.Name, AE_Code__c, Revenue_Amount__c,
                   Period_Month__c, Period_Year__c, Revenue_Type__c,
                   Source_System__r.Code__c, Station_Code__c, Late_Disposition__c
            FROM   Actual_Revenue__c
            WHERE  Is_Late__c = true
              AND  (Late_Disposition__c = null OR Late_Disposition__c = 'Pending')
            ORDER BY Period_Year__c DESC, Period_Month__c DESC, Advertiser__r.Name
            LIMIT  :size
            OFFSET :offset
        ];

        List<LateActualRow> rows = new List<LateActualRow>();
        for (Actual_Revenue__c a : actuals) {
            LateActualRow row = new LateActualRow();
            row.actualId       = a.Id;
            row.advertiserName = a.Advertiser__r?.Name;
            row.aeCode         = a.AE_Code__c;
            row.revenueAmount  = a.Revenue_Amount__c;
            row.periodMonth    = a.Period_Month__c != null ? a.Period_Month__c.intValue()  : null;
            row.periodYear     = a.Period_Year__c  != null ? a.Period_Year__c.intValue()   : null;
            row.revenueType    = a.Revenue_Type__c;
            row.sourceSystem   = a.Source_System__r?.Code__c;
            row.stationCode    = a.Station_Code__c;
            row.disposition    = a.Late_Disposition__c != null ? a.Late_Disposition__c : 'Pending';
            rows.add(row);
        }

        LateActualResult result = new LateActualResult();
        result.rows       = rows;
        result.totalCount = total;
        return result;
    }

    // ── Single-row actions ────────────────────────────────────────────────────

    @AuraEnabled
    public static void acceptLateActual(Id actualId) {
        setDisposition(new Set<Id>{ actualId }, 'Accepted');
    }

    @AuraEnabled
    public static void rejectLateActual(Id actualId) {
        setDisposition(new Set<Id>{ actualId }, 'Rejected');
    }

    // ── Bulk action ───────────────────────────────────────────────────────────

    @AuraEnabled
    public static void bulkDispose(List<Id> actualIds, String disposition) {
        if (disposition != 'Accepted' && disposition != 'Rejected') {
            throw new AuraHandledException('Invalid disposition: ' + disposition);
        }
        setDisposition(new Set<Id>(actualIds), disposition);
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    @TestVisible
    static void setDisposition(Set<Id> ids, String disposition) {
        List<Actual_Revenue__c> toUpdate = [
            SELECT Id, Late_Disposition__c
            FROM   Actual_Revenue__c
            WHERE  Id IN :ids
              AND  Is_Late__c = true
        ];
        for (Actual_Revenue__c a : toUpdate) {
            a.Late_Disposition__c = disposition;
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
