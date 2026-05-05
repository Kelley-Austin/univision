public virtual class ResponseProcessor implements IResponseProcessor {
    
    Log responseLog {get;set;}
    
    public virtual Log getResponse(RESTHandler.Response thisResponse, Log requestLog){
        Log responseLog = New Log();
        responseLog.CorrelationId = requestLog.CorrelationId;
        responseLog.LogEventName = requestLog.LogEventName;
        responseLog.ObjectReferenceId = requestLog.ObjectReferenceId;
        
        //responseLog.EventKey
        //responseLog.ExpirationDate
        //responseLog.Mantissa
        
        responseLog.Message = thisResponse.statusCode + ' ' + thisResponse.status;
        responseLog.Type='Response'; 
        responseLog.Content = JSON.serialize(thisResponse);
        
        return responseLog;
    }
    
    public virtual String toJSON(){
        return JSON.serialize(responseLog);
    }
}