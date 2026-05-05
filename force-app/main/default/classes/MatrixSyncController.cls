public with sharing class MatrixSyncController {

    public class SyncStatus {
        @AuraEnabled public String status;
        @AuraEnabled public Integer recordsProcessed;
        @AuraEnabled public Integer recordsFailed;
        @AuraEnabled public String errorDetail;
        @AuraEnabled public String syncType;
        @AuraEnabled public Datetime syncTime;
        @AuraEnabled public Boolean isScheduled;
        @AuraEnabled public Datetime nextScheduledRun;
        @AuraEnabled public Boolean hasRun;
    }

    @AuraEnabled(cacheable=true)
    public static SyncStatus getLastSyncStatus() {
        SyncStatus result = new SyncStatus();

        List<Matrix_Sync_Log__c> logs = [
            SELECT Status__c, Records_Processed__c, Records_Failed__c,
                   Error_Detail__c, Sync_Type__c, CreatedDate
            FROM Matrix_Sync_Log__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        result.hasRun = !logs.isEmpty();
        if (!logs.isEmpty()) {
            Matrix_Sync_Log__c log = logs[0];
            result.status = log.Status__c;
            result.recordsProcessed = log.Records_Processed__c != null ? Integer.valueOf(log.Records_Processed__c) : 0;
            result.recordsFailed = log.Records_Failed__c != null ? Integer.valueOf(log.Records_Failed__c) : 0;
            result.errorDetail = log.Error_Detail__c;
            result.syncType = log.Sync_Type__c;
            result.syncTime = log.CreatedDate;
        }

        List<CronTrigger> cts = [
            SELECT NextFireTime FROM CronTrigger
            WHERE CronJobDetail.Name = :MatrixInventoryScheduler.JOB_NAME
            AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 1
        ];
        result.isScheduled = !cts.isEmpty();
        result.nextScheduledRun = cts.isEmpty() ? null : cts[0].NextFireTime;

        return result;
    }

    @AuraEnabled
    public static void triggerManualSync() {
        System.enqueueJob(new MatrixInventorySyncQueueable(true));
    }

    @AuraEnabled
    public static void rescheduleSync(Integer hour) {
        if (hour == null || hour < 0 || hour > 23) {
            throw new AuraHandledException('Hour must be between 0 and 23.');
        }
        MatrixInventoryScheduler.scheduleAt(hour);
    }
}
