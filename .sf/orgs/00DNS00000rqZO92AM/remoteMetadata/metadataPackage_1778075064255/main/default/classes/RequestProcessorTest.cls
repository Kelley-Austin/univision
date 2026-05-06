@isTest
public class RequestProcessorTest {

    @isTest
    static void testGetRequestWithLog() {
        // Create a test log record
        Log testLog = new Log( 'eventName',  'message',  'content',  'correlationId');

        // Instantiate the RequestProcessor class
        RequestProcessor processor = new RequestProcessor();
        
        // Call getRequest() with the test log
        RESTHandler.Request req = processor.getRequest(testLog);

        // Validate that the request object was properly initialized
        System.assertNotEquals(req, null, 'Request object should not be null');
        System.assertEquals(testLog.Content, req.body, 'Request body should match log content');
    }

    @isTest
    static void testToJSON() {
        // Create a test log record
        Log testLog = new Log( 'eventName',  'message',  'content',  'correlationId');

        // Instantiate the RequestProcessor class
        RequestProcessor processor = new RequestProcessor();
        
        // Generate the request object
        processor.getRequest(testLog);
        
        // Convert request object to JSON
        String jsonOutput = processor.toJSON();
        
        // Validate that JSON output is not null and contains expected fields
        System.assertNotEquals(jsonOutput, null, 'JSON output should not be null');
        System.assert(jsonOutput.contains(testLog.Content), 'JSON output should contain the log content');
    }

    @isTest
    static void testGetRequestFromJSON() {
        // Create a JSON representation of a request
        String requestJSON = '{"body":"Test body","method":"POST","path":"/api/resource"}';
        
        // Call the static method to convert JSON to a request object
        RESTHandler.Request req = RequestProcessor.getRequest(requestJSON);
        
        // Validate the deserialization process
        System.assertNotEquals(req, null, 'Deserialized request object should not be null');
        System.assertEquals('Test body', req.body, 'Body should match the JSON value');
        System.assertEquals('POST', req.method, 'Method should match the JSON value');
        System.assertEquals('/api/resource', req.path, 'Path should match the JSON value');
    }
}