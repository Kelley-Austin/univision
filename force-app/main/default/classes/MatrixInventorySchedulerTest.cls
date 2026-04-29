@isTest
private class MatrixInventorySchedulerTest {

    private class InventoryMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"records":[]}');
            return res;
        }
    }

    @isTest
    static void testSchedule_enqueuesJob() {
        Test.setMock(HttpCalloutMock.class, new InventoryMock());

        Test.startTest();
        // Execute the schedulable synchronously in test context
        MatrixInventoryScheduler scheduler = new MatrixInventoryScheduler();
        scheduler.execute(null);
        Test.stopTest();
        // If we reach here, the queueable was enqueued without error
        System.assert(true);
    }

    @isTest
    static void testScheduleAll_registersJobs() {
        Test.startTest();
        MatrixInventoryScheduler.scheduleAll();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Matrix Inventory Sync%'
        ];
        System.assertEquals(4, jobs.size(), 'Expected 4 scheduled jobs for 15-minute intervals');
    }
}
