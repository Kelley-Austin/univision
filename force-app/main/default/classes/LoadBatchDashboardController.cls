public with sharing class LoadBatchDashboardController {

    @AuraEnabled(cacheable=true)
    public static List<Load_Batch__c> getRecentBatches(Id sourceSystemId, Integer limitCount) {
        if (limitCount == null || limitCount <= 0) limitCount = 20;
        return [
            SELECT Id, Name, File_Name__c, Status__c, Row_Count__c, Error_Count__c, Processed_At__c, CreatedDate
            FROM Load_Batch__c
            WHERE Source_System__c = :sourceSystemId
            ORDER BY CreatedDate DESC
            LIMIT :limitCount
        ];
    }

    @AuraEnabled(cacheable=true)
    public static BatchSummary getSummary(Id sourceSystemId) {
        Datetime oneDayAgo = Datetime.now().addDays(-1);
        AggregateResult[] agg = [
            SELECT SUM(Row_Count__c) totalRows, SUM(Error_Count__c) totalErrors, COUNT(Id) batchCount
            FROM Load_Batch__c
            WHERE Source_System__c = :sourceSystemId AND CreatedDate >= :oneDayAgo
        ];
        Decimal rows = (Decimal) agg[0].get('totalRows');
        Decimal errors = (Decimal) agg[0].get('totalErrors');
        Integer batches = Integer.valueOf(agg[0].get('batchCount'));
        return new BatchSummary(
            rows != null ? rows.intValue() : 0,
            errors != null ? errors.intValue() : 0,
            batches
        );
    }

    public class BatchSummary {
        @AuraEnabled public Integer totalRowsToday;
        @AuraEnabled public Integer totalErrorsToday;
        @AuraEnabled public Integer batchCount;
        public BatchSummary(Integer r, Integer e, Integer b) {
            totalRowsToday = r; totalErrorsToday = e; batchCount = b;
        }
    }
}
