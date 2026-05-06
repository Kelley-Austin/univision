/** 
* Mock response class to use in the test classes for the RESTHandler class.
* 
* @author Patrick Stephens
* @version 1.0 
*/
public without sharing class RESTHandlerMock implements HttpCalloutMock {
    public String body {
        get{
            if(body==null){
                body='{"status":"success"}';
            }
            return body;
        }
        set;
    }
    public HTTPResponse respond(HTTPRequest req) {
        // Create a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody(body);
        res.setStatusCode(200);
         res.setStatus('OK');
        return res;
    }
}