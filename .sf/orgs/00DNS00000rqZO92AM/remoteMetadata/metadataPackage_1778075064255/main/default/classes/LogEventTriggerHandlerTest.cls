@IsTest
private class LogEventTriggerHandlerTest {
    
    @IsTest
    static void testAfterInsert() {
        Test.startTest();
        
        // Insert dummy LogEvent__e records to trigger the handler
        List<LogEvent__e> testEvents = new List<LogEvent__e>{
            
            new LogEvent__e(
                CorrelationId__c = 'TestCorrelation1',
                RunningUserID__c = UserInfo.getUserId()
            ),
            new LogEvent__e(
                CorrelationId__c = 'TestCorrelation2',
                RunningUserID__c = UserInfo.getUserId()
            ),
                new LogEvent__e(
                CorrelationId__c = 'TestCorrelation1',
                RunningUserID__c = UserInfo.getUserId()
            ),
            new LogEvent__e(
                CorrelationId__c = 'TestCorrelation2',
                RunningUserID__c = UserInfo.getUserId()
            )
        };
            
        // Simulate Platform Event publishing
       list<Database.SaveResult> sr = EventBus.publish(testEvents);

        // Ensure platform events are processed
        Test.stopTest();

        // Verify that Log__c records were created
        List<Log__c> logs = [SELECT Id, CorrelationId__c, RunningUserID__c, ReplayId__c, EventUuid__c FROM Log__c];
        System.assertEquals(2, logs.size(), 'Two Log__c records should be created');
        
        // Verify that LogDetail__c records were created
        List<LogDetail__c> logDetails = [SELECT Id, Log__c, CorrelationId__c FROM LogDetail__c];
        System.assert(logDetails.size() > 0, 'LogDetail__c records should be created');

        // Ensure correlation IDs are correctly assigned
        Set<String> correlationIds = new Set<String>();
        for (Log__c log : logs) {
            correlationIds.add(log.CorrelationId__c);
        }
        System.assert(correlationIds.contains('TestCorrelation1'), 'CorrelationId TestCorrelation1 should exist');
        System.assert(correlationIds.contains('TestCorrelation2'), 'CorrelationId TestCorrelation2 should exist');
    }
}