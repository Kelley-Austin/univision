@IsTest
private class MatrixSyncInvocableTest {

    @IsTest
    static void triggerSync_enqueuesJob_returnsConfirmation() {
        MatrixSyncInvocable.TriggerRequest req = new MatrixSyncInvocable.TriggerRequest();

        Test.startTest();
        List<String> results = MatrixSyncInvocable.triggerSync(new List<MatrixSyncInvocable.TriggerRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].contains('queued'), 'Result message should confirm queueing');
    }

    @IsTest
    static void reschedule_validHour_schedulesAndReturnsSuccess() {
        MatrixRescheduleInvocable.RescheduleRequest req = new MatrixRescheduleInvocable.RescheduleRequest();
        req.scheduleHour = 5;

        Test.startTest();
        List<MatrixRescheduleInvocable.RescheduleResult> results =
            MatrixRescheduleInvocable.reschedule(new List<MatrixRescheduleInvocable.RescheduleRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assert(results[0].message.contains('5:00 UTC'), 'Message should confirm the hour');
        System.assert(MatrixInventoryScheduler.isScheduled());
    }

    @IsTest
    static void reschedule_invalidHour_returnsFailure() {
        MatrixRescheduleInvocable.RescheduleRequest req = new MatrixRescheduleInvocable.RescheduleRequest();
        req.scheduleHour = 99;

        Test.startTest();
        List<MatrixRescheduleInvocable.RescheduleResult> results =
            MatrixRescheduleInvocable.reschedule(new List<MatrixRescheduleInvocable.RescheduleRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(String.isNotBlank(results[0].message), 'Error message should be populated');
    }

    @IsTest
    static void getScheduleInfo_noJob_returnsNotScheduled() {
        MatrixScheduleInfoInvocable.ScheduleInfoRequest req = new MatrixScheduleInfoInvocable.ScheduleInfoRequest();

        Test.startTest();
        List<MatrixScheduleInfoInvocable.ScheduleInfoResult> results =
            MatrixScheduleInfoInvocable.getScheduleInfo(new List<MatrixScheduleInfoInvocable.ScheduleInfoRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isScheduled);
        System.assertEquals('Not scheduled', results[0].nextFireTimeText);
        System.assertEquals(null, results[0].nextFireTime);
    }

    @IsTest
    static void getScheduleInfo_withJob_returnsScheduledInfo() {
        MatrixInventoryScheduler.scheduleAt(3);

        MatrixScheduleInfoInvocable.ScheduleInfoRequest req = new MatrixScheduleInfoInvocable.ScheduleInfoRequest();

        Test.startTest();
        List<MatrixScheduleInfoInvocable.ScheduleInfoResult> results =
            MatrixScheduleInfoInvocable.getScheduleInfo(new List<MatrixScheduleInfoInvocable.ScheduleInfoRequest>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].isScheduled);
        System.assertNotEquals(null, results[0].nextFireTime);
        System.assertNotEquals('Not scheduled', results[0].nextFireTimeText);
    }
}
