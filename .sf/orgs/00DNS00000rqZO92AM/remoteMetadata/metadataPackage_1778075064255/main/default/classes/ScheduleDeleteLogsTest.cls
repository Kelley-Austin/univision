@isTest
public class ScheduleDeleteLogsTest {

    @isTest
    static void testExecute() {
        Test.startTest();
        
        // Instantiate and execute the scheduled job
        ScheduleDeleteLogs scheduler = new ScheduleDeleteLogs();
        scheduler.execute(null);
        
        Test.stopTest();

        // Verify that the Queueable job was enqueued
        System.assertEquals(1, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'], 
            'QueueableDeleteLogs should have been enqueued');
    }

}