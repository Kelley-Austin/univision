@isTest
public class QueueableDeleteLogsTest {
    
    @testSetup
    static void setupTestData() {
        // CreatedDate is system-managed and not directly writeable on insert.
        // Insert first, then back-date via Test.setCreatedDate so the
        // QueueableDeleteLogs job sees rows older than its 30-day cutoff.
        Datetime oldDate = System.now().addDays(-31);

        List<Log__c> oldLogs = new List<Log__c>();
        for (Integer i = 0; i < 10; i++) {
            oldLogs.add(new Log__c(Type__c = 'INFO'));
        }
        insert oldLogs;
        for (Log__c lg : oldLogs) {
            Test.setCreatedDate(lg.Id, oldDate);
        }

        List<Log__c> currentLogs = new List<Log__c>();
        for (Integer i = 0; i < 5; i++) {
            currentLogs.add(new Log__c(Type__c = 'DELETE'));
        }
        insert currentLogs;
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