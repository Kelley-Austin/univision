@isTest
public class QueueableDeleteLogsTest {
    
    @testSetup
    static void setupTestData() {
        List<Log__c> logs = new List<Log__c>();
        Datetime oldDate = System.now().addDays(-31); // Logs older than 30 days to trigger deletion
        
        for (Integer i = 0; i < 10; i++) {
            logs.add(new Log__c(CreatedDate = oldDate, Type__c = 'INFO'));
        }
        for (Integer i = 0; i < 5; i++) {
            logs.add(new Log__c(Type__c = 'DELETE'));
        }
        insert logs;
    }
    
    @isTest
    static void testQueueableDeleteLogs() {
        Test.startTest();
        
        // Instantiate and execute the queueable job
        QueueableDeleteLogs queueableJob = new QueueableDeleteLogs();
        System.enqueueJob(queueableJob);
        
        Test.stopTest();
        
        // Verify that logs are deleted
        List<Log__c> remainingLogs = [SELECT Id FROM Log__c];
        System.assertEquals(0, remainingLogs.size(), 'All logs should be deleted');
    }

    @isTest
    static void testQueueableDeleteLogsWithMockParam() {
        Test.startTest();

        QueueableDeleteLogs queueableJob = new QueueableDeleteLogs();
        System.enqueueJob(queueableJob);
        
        Test.stopTest();
        
        // Verify that logs are deleted
        List<Log__c> remainingLogs = [SELECT Id FROM Log__c];
        System.assertEquals(0, remainingLogs.size(), 'All logs should be deleted');
    }
}