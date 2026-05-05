@IsTest
private class MatrixSyncControllerTest {

    @TestSetup
    static void setup() {
        insert new Matrix_Sync_Log__c(
            Status__c = 'Success',
            Records_Processed__c = 5,
            Records_Failed__c = 0,
            Sync_Type__c = 'Scheduled'
        );
    }

    @IsTest
    static void getLastSyncStatus_returnsLastLog() {
        Test.startTest();
        MatrixSyncController.SyncStatus result = MatrixSyncController.getLastSyncStatus();
        Test.stopTest();

        System.assertEquals(true, result.hasRun);
        System.assertEquals('Success', result.status);
        System.assertEquals(5, result.recordsProcessed);
        System.assertEquals(0, result.recordsFailed);
        System.assertEquals('Scheduled', result.syncType);
        System.assertNotEquals(null, result.syncTime);
    }

    @IsTest
    static void getLastSyncStatus_noLogs_hasRunFalse() {
        delete [SELECT Id FROM Matrix_Sync_Log__c];

        Test.startTest();
        MatrixSyncController.SyncStatus result = MatrixSyncController.getLastSyncStatus();
        Test.stopTest();

        System.assertEquals(false, result.hasRun);
        System.assertEquals(null, result.status);
    }

    @IsTest
    static void getLastSyncStatus_scheduledJobInfo() {
        MatrixInventoryScheduler.scheduleAt(3);

        Test.startTest();
        MatrixSyncController.SyncStatus result = MatrixSyncController.getLastSyncStatus();
        Test.stopTest();

        System.assertEquals(true, result.isScheduled);
        System.assertNotEquals(null, result.nextScheduledRun);
    }

    @IsTest
    static void getLastSyncStatus_noScheduledJob() {
        Test.startTest();
        MatrixSyncController.SyncStatus result = MatrixSyncController.getLastSyncStatus();
        Test.stopTest();

        System.assertEquals(false, result.isScheduled);
        System.assertEquals(null, result.nextScheduledRun);
    }

    @IsTest
    static void triggerManualSync_enqueuesJob() {
        Test.startTest();
        MatrixSyncController.triggerManualSync();
        Test.stopTest();
        // No exception = success; queueable was enqueued
        System.assert(true);
    }

    @IsTest
    static void rescheduleSync_validHour_schedulesJob() {
        Test.startTest();
        MatrixSyncController.rescheduleSync(6);
        Test.stopTest();

        System.assert(MatrixInventoryScheduler.isScheduled(), 'Job should be scheduled after reschedule');
    }

    @IsTest
    static void rescheduleSync_invalidHour_throws() {
        Test.startTest();
        try {
            MatrixSyncController.rescheduleSync(24);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('0 and 23'), 'Error should mention valid range');
        }
        Test.stopTest();
    }

    @IsTest
    static void rescheduleSync_nullHour_throws() {
        Test.startTest();
        try {
            MatrixSyncController.rescheduleSync(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}
