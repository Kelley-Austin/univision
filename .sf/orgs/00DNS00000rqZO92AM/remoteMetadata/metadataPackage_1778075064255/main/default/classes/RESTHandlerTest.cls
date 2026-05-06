@isTest
public class RESTHandlerTest {


    @isTest
    static void testConstructorWithRequest() {
        RESTHandler.Request req = new RESTHandler.Request();
        req.credential = 'Test_Credential';
        req.method = 'POST';
        req.path = '/api/test';
        req.body = '{"name":"Test"}';

        // Instantiate RESTHandler using Request object
        RESTHandler handler = new RESTHandler(req);

        System.assertNotEquals(handler, null, 'RESTHandler instance should not be null');
        System.assertEquals(req, handler.request, 'Request object should be the same');
    }

    @isTest
    static void testConstructorWithLog() {

       	Log testLog = new Log( 'eventName',  'message',  '{"body":"Test Body","method":"POST","path":"/api/test"}',  'correlationId');

        // Instantiate RESTHandler using Log__c object
        RESTHandler handler = new RESTHandler(testLog);

        System.assertNotEquals(handler.request, null, 'Request object should not be null');
        System.assertEquals('/api/test', handler.request.path, 'Path should match log content');
        System.assertEquals('Test Body', handler.request.body, 'Body should match log content');
    }

    @isTest
    static void testConstructorWithNamedCredential() {
        RESTHandler handler = new RESTHandler('My_Credential', 'POST', '/test', '{"key":"value"}', 6000);

        System.assertNotEquals(handler.request, null, 'Request should be initialized');
        System.assertEquals('My_Credential', handler.request.credential, 'Credential should match');
        System.assertEquals('POST', handler.request.method, 'Method should be POST');
        System.assertEquals('/test', handler.request.path, 'Path should match');
        System.assertEquals('{"key":"value"}', handler.request.body, 'Body should match');
    }

    @isTest
    static void testDoCalloutWithMock() {
        // Mock HTTP response
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new RESTHandlerMock());

        RESTHandler handler = new RESTHandler('My_Credential', 'GET', '/mock', null);
        HttpResponse response = handler.doCallout();

        Test.stopTest();

        System.assertEquals(200, response.getStatusCode(), 'Status code should be 200');
        System.assert(response.getBody().contains('success'), 'Response body should contain success');
    }

    @isTest
    static void testWrapCallout() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new RESTHandlerMock());

        RESTHandler handler = new RESTHandler('My_Credential', 'POST', '/wrap', '{"data":"value"}');
        RESTHandler.Response response = handler.wrapCallout();

        Test.stopTest();

        System.assertEquals(200, response.statusCode, 'Status code should be 200');
        System.assertEquals('OK', response.status, 'Status should be OK');
        System.assert(response.body.contains('success'), 'Response body should contain success');
    }

    @isTest
    static void testResponseClass() {
        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setBody('{"message":"Test Response"}');
        mockResponse.setStatusCode(201);
        mockResponse.setStatus('Created');
        
        RESTHandler.Response response = new RESTHandler.Response(mockResponse);
        
        System.assertEquals(201, response.statusCode, 'Status code should be 201');
        System.assertEquals('Created', response.status, 'Status should be Created');
        System.assert(response.body.contains('Test Response'), 'Body should contain "Test Response"');
    }

}