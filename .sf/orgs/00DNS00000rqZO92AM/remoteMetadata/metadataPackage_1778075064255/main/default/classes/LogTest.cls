@isTest
public class LogTest {
    
    @isTest
    static void testLogConstructors() {
        // Testing default constructor
        new Log();
        
        // Testing overloaded constructors
        new Log('Event1', 'Test Message', 'CorrelationId1');
        new Log('Event2', 'Test Message 2', 'Test Content', 'CorrelationId2');
        new Log('Event3', 'TypeA', 'Message 3', 'Key3', 'Content3', 'CorrelationId3');
    }
    
    @isTest
    static void testTruncation() {
        Log log = new Log();
        
        log.Message = 'X'.repeat(300); // Exceeds 255 characters
        log.Content = 'Y'.repeat(140000); // Exceeds 131072 characters
    }
    
    @isTest
    public static void testToLogMethods() {
        Log l = new Log('TestEvent', 'TestType', 'TestMessage', 'TestKey', 'TestContent', 'TestCorrelation');
        Map<String, Object> mapLogs = new Map<String, Object>();
        Log__c logObject = new Log__c();
        LogDetail__c logDetail = new LogDetail__c();
        
        mapLogs.put('Log__c', 'Test');
        
        // Converting to Log
        Log.toLog(l);
        Log.toLog(mapLogs);
        Log.toLog(logObject);
        Log.toLog(logDetail);
        
        // Converting a list of Logs
        List<Object> logs = new List<Object>{ l, l };
            List<Log__c> logsObjects = new List<Log__c>{ logObject, logObject };
                List<LogDetail__c> logsDetails = new List<LogDetail__c>{ logDetail, logDetail };
                    
                    Log.toLogs(logs);
        Log.toLogs(logsObjects);
        Log.toLogs(logsDetails);
        
    }
    
    @isTest
    static void testCacheMethods() {
        Log log = new Log('CacheTestEvent', 'Test Message', 'TestCorrelation');
        log.EventKey = 'TestCacheKey';
        
        try {
            log.cacheEventKey(60);
            log.clearCachedEventKey();
        } catch (Exception e) {
            System.debug('Skipping cache test due to missing default partition: ' + e.getMessage());
        }
    }
    
    @isTest
    static void testEmitMethods() {
        Log log = new Log('EmitTest', 'Emit message', 'EmitCorrelation');
        
        Test.startTest();
        log.emit();
        log.emitIm();
        Test.stopTest();
    }
    
    @isTest
    static void testCreateLogEvent() {
        Log log = new Log('LogEventTest', 'TestType', 'Test Message', 'TestKey', 'Test Content', 'TestCorrelation');
        
        Test.startTest();
        log.createLogEvent();
        Test.stopTest();
    }
    
    @isTest
    static void testCreateImLogEvent() {
        Log log = new Log('ImLogEventTest', 'TestType', 'Test Message', 'TestKey', 'Test Content', 'TestCorrelation');
        
        Test.startTest();
        log.createImLogEvent();
        Test.stopTest();
    }
    
    @isTest
    static void testGetMethods() {
        Log log = new Log('GetTestEvent', 'TestType', 'TestMessage', 'TestKey', 'TestContent', 'TestCorrelation');
        
        // Retrieving properties
        log.getStr('LogEventName');
        log.get('Message');
    }
    
    @isTest
    static void testToLogMap() {
        List<Log> logs = new List<Log>{
            new Log('Event1', 'Type1', 'Message1', 'Key1', 'Content1', 'Correlation1'),
                new Log('Event1', 'Type2', 'Message2', 'Key2', 'Content2', 'Correlation1'),
                new Log('Event2', 'Type3', 'Message3', 'Key3', 'Content3', 'Correlation2')
                };
                    
                    Log.toLogMap(logs);
    }
    
    @isTest
    static void testOnFailureWithRetries() {
        // Creating a mock retry map with failed log events
        Map<String, Log> retryMap = new Map<String, Log>();
        Log log1 = new Log('TestEvent', 'TestMessage', 'Correlation1');
        Log log2 = new Log('TestEvent2', 'TestMessage2', 'Correlation2');
        
        // Simulating event UUIDs
        String uuid1 = 'UUID1';
        String uuid2 = 'UUID2';
        retryMap.put(uuid1, log1);
        retryMap.put(uuid2, log2);
        
        // Creating callback instance
        Log.LogEventCallback callback = new Log.LogEventCallback(retryMap);
        
        // Simulating FailureResult behavior using a mock class
        MockFailureResult failureResult = new MockFailureResult(new List<String>{uuid1, uuid2});
        
        Test.startTest();
        callback.onFailure(failureResult);
        Test.stopTest();
    }
    
    @isTest
    static void testOnFailureWithMaxRetriesExceeded() {
        // Mocking retry map
        Map<String, Log> retryMap = new Map<String, Log>();
        Log log1 = new Log('FailedEvent', 'ErrorMessage', 'FailedCorrelation');
        retryMap.put('UUID1', log1);
        
        // Creating callback instance
        Log.LogEventCallback callback = new Log.LogEventCallback(retryMap);
        
        Test.startTest();
        for (Integer i = 0; i <= logX.getParamInt('PublishRetries'); i++) {
            MockFailureResult failureResult = new MockFailureResult(new List<String>{'UUID1'});
            callback.onFailure(failureResult);
        }
        Test.stopTest();
    }
    
    // Mock class to simulate EventBus.FailureResult
    private class MockFailureResult implements EventBus.FailureResult {
        private List<String> eventUuids;
        
        public MockFailureResult(List<String> eventUuids) {
            this.eventUuids = eventUuids;
        }
        
        public List<String> getEventUuids() {
            return eventUuids;
        }
    }
}