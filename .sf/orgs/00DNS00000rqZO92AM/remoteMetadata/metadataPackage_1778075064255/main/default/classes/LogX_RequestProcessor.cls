public without sharing class LogX_RequestProcessor extends RequestProcessor implements IRequestProcessor {
    RESTHandler.Request req {get;set;}
    public override RESTHandler.Request getRequest(Log thisLog){
        req = new RESTHandler.Request();

        //use the content of this log to generate the Request
        
        switch on thisLog.Type {
            when 'Get Accounts' {
                List<String> accountIds = (List<String>)JSON.deserialize(thisLog.Content, List<String>.class);
                List<Account> accounts = [SELECT Id, Name FROM Account WHERE Id IN :accountIds WITH USER_MODE];
                req.body = JSON.serializePretty(accounts);
                req.contentType = 'application/json';
                req.credential=null;
                req.method='POST';
                req.path='/services/data/v40.0/sobjects/Account';
                
            }
            when else {
                req.body = thisLog.content;
        
                // req.contentType;
                // req.credential;
                // req.method;
                // req.path;

                RESTHandler.HTTPHeader header = new RESTHandler.HTTPHeader();
                    header.name = 'test';
                    header.value = 'test';
                req.headers = new List<RESTHandler.HTTPHeader>{header};
                
                req.testResponseBody = '{"test":"test"}';
                req.testResponseStatus = 'SUCCESS';
                req.testResponseStatusCode = 200;
            }
        }

        return req;
    }
    public override String toJSON(){
        return JSON.serializePretty(req);
    }
}