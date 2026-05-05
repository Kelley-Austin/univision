public virtual class RequestProcessor implements IRequestProcessor {
    RESTHandler.Request req {get;set;}

    public virtual RESTHandler.Request getRequest(Log thisLog){
        req = New RESTHandler.Request();
        
        req.body = thisLog.content;
        
        // req.contentType;
        // req.credential;
        // req.headers;
        // req.method;
        // req.path;
        
        
        // req.testResponseBody;
        // req.testResponseStatus;
        // req.testResponseStatusCode;


        return req;
    }
    public virtual String toJSON(){
        return JSON.serialize(req);
    }
    public static RESTHandler.Request getRequest(String requestJSON){
        return (RESTHandler.Request)JSON.deserialize(requestJSON, RESTHandler.Request.class);
    }
}