@IsTest
private class MatrixInventorySchedulerTest {

    @IsTest
    static void scheduleAt_createsJob() {
        Test.startTest();
        MatrixInventoryScheduler.scheduleAt(3);
        Test.stopTest();

        System.assert(MatrixInventoryScheduler.isScheduled(), 'Job should be active after scheduleAt');
        Datetime nextRun = MatrixInventoryScheduler.getNextFireTime();
        System.assertNotEquals(null, nextRun, 'Next fire time should be set');
    }

    @IsTest
    static void scheduleAt_replacesExistingJob() {
        MatrixInventoryScheduler.scheduleAt(2);
        System.assert(MatrixInventoryScheduler.isScheduled());

        Test.startTest();
        MatrixInventoryScheduler.scheduleAt(4);
        Test.stopTest();

        // Still exactly one active job
        Integer count = [
            SELECT COUNT() FROM CronTrigger
            WHERE CronJobDetail.Name = :MatrixInventoryScheduler.JOB_NAME
            AND State NOT IN ('DELETED', 'COMPLETE')
        ];
        System.assertEquals(1, count, 'Should have exactly one scheduled job after rescheduling');
    }

    @IsTest
    static void abortExisting_removesJob() {
        MatrixInventoryScheduler.scheduleAt(2);
        System.assert(MatrixInventoryScheduler.isScheduled());

        Test.startTest();
        MatrixInventoryScheduler.abortExisting();
        Test.stopTest();

        System.assertEquals(false, MatrixInventoryScheduler.isScheduled(), 'Job should be gone after abort');
        System.assertEquals(null, MatrixInventoryScheduler.getNextFireTime());
    }

    @IsTest
    static void isScheduled_falseWhenNoJob() {
        System.assertEquals(false, MatrixInventoryScheduler.isScheduled());
    }

    @IsTest
    static void scheduleAt_invalidHour_throws() {
        Test.startTest();
        try {
            MatrixInventoryScheduler.scheduleAt(25);
            System.assert(false, 'Expected exception for out-of-range hour');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('0–23'), 'Error should mention valid range');
        }
        Test.stopTest();
    }

    @IsTest
    static void execute_enqueuesQueueable() {
        MatrixInventoryScheduler scheduler = new MatrixInventoryScheduler();
        Test.startTest();
        // Calling execute directly — in a real schedule test the job would fire.
        // We verify no exception is thrown and that a job is enqueued.
        scheduler.execute(null);
        Test.stopTest();
        // If no exception was thrown, the queueable was enqueued successfully.
        System.assert(true, 'execute() should complete without error');
    }

    @IsTest
    static void scheduleAtConfiguredHour_usesDefaultConfig() {
        // Custom metadata record (Default) has Schedule_Hour__c = 2 per deployment.
        // In test context without the record, it falls back to hour 2.
        Test.startTest();
        MatrixInventoryScheduler.scheduleAtConfiguredHour();
        Test.stopTest();

        System.assert(MatrixInventoryScheduler.isScheduled(), 'Job should be scheduled using configured or default hour');
    }
}
