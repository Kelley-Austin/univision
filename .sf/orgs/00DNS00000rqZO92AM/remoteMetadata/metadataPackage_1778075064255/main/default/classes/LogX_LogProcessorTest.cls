@IsTest
private class LogX_LogProcessorTest {
    @IsTest
    static void testProcessLogs() {
        // Query test logs
       List<Log> testLogs = new List<Log>{
            new Log('CalloutEvent', 'Callout', 'Processing callout', null, 'Callout Content', 'CID-1'),
            new Log('LogThenCalloutEvent', 'LogThenCallout', 'Enqueue Callout', null, null, 'CID-2'),
            new Log('ResponseEvent', 'Response', 'Processing response', null, 'Response Content', 'CID-3'),
            new Log('UnknownEvent', 'Unknown', 'Unknown processing', null, null, 'CID-4') // Should be ignored
        };
        // Instantiate LogX_LogProcessor and set logs
        LogX_LogProcessor processor = new LogX_LogProcessor();
        processor.setLogs(testLogs);

        Test.startTest();
        LogProcessor.Result result = processor.processLogs();
        Test.stopTest();

        // Validate result
        System.assertNotEquals(result, null, 'Result should not be null');
        
    }

    @IsTest
    static void testProcessLog_Callout() {
        Log testLog = new Log('CalloutEvent', 'Callout', 'Processing callout', null, 'Callout Content', 'CID-1');

        LogX_LogProcessor processor = new LogX_LogProcessor();
        
        Test.startTest();
        Log resultLog = processor.processLog(testLog);
        Test.stopTest();

        // Validate that a log event was created
        System.assertNotEquals(resultLog, null, 'Result log should not be null for Callout');
    }

    @IsTest
    static void testProcessLog_LogThenCallout() {
        Log testLog = new Log('LogThenCalloutEvent', 'LogThenCallout', 'Enqueue Callout', null, null, 'CID-2');

        LogX_LogProcessor processor = new LogX_LogProcessor();

        Test.startTest();
        Log resultLog = processor.processLog(testLog);
        Test.stopTest();

        System.assertNotEquals(resultLog, null, 'Result log should not be null for LogThenCallout');
        System.assertEquals('Callout', resultLog.Type, 'LogThenCallout should be logged first before processing callout');
    }

    @IsTest
    static void testProcessLog_Response() {
        Log testLog = new Log('ResponseEvent', 'Response', 'Processing response', null, 'Response Content', 'CID-3');

        LogX_LogProcessor processor = new LogX_LogProcessor();

        Test.startTest();
        Log resultLog = processor.processLog(testLog);
        Test.stopTest();

        System.assertNotEquals(resultLog, null, 'Result log should not be null for Response');
        System.assertEquals('Finalized', resultLog.Type, 'Response log should be processed as Finalized');
    }

    @IsTest
    static void testProcessLog_UnknownType() {
        Log testLog = new Log('UnknownEvent', 'Unknown', 'Unknown processing', null, null, 'CID-4');

        LogX_LogProcessor processor = new LogX_LogProcessor();

        Test.startTest();
        Log resultLog = processor.processLog(testLog);
        Test.stopTest();

        System.assertEquals(resultLog, null, 'Unknown log types should return null');
    }
}