@isTest
public class LogFlowTest {

    @isTest
    static void testLogEvents_Success() {
        List<LogFlow.LogRequest> requests = new List<LogFlow.LogRequest>();
        LogFlow.LogRequest logRequest = new LogFlow.LogRequest();
        logRequest.logEventName = 'Test Event';
        logRequest.type = 'Info';
        logRequest.message = 'This is a test log message';
        logRequest.content = 'Test content';
        logRequest.eventKey = 'TestKey';
        logRequest.correlationId = '12345';
        logRequest.expirationDate = Date.today().addDays(30);
        logRequest.mantissa = 123.45;

        requests.add(logRequest);
        Test.startTest();
        List<LogFlow.LogRequest> response = LogFlow.LogEvents(requests);
        Test.stopTest();
    }
    
    
    class LogRequest {
        String logEventName;
        String type;
        String correlationId;
        String message;
        String content;
        String eventKey;
        Id objectReferenceId;
        Date expirationDate;
        Decimal mantissa;
        Boolean isSuccess;
        String errorMessage;
    }
}