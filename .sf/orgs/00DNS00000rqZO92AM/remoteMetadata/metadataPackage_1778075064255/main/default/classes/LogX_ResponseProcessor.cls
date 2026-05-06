public without sharing class LogX_ResponseProcessor extends ResponseProcessor implements IResponseProcessor {
    public override Log getResponse(RESTHandler.Response thisResponse, Log requestLog){
        Log responseLog = New Log();
        responseLog.CorrelationId = requestLog.CorrelationId;
        responseLog.LogEventName = requestLog.LogEventName;
        responseLog.ObjectReferenceId = requestLog.ObjectReferenceId;
        
        //responseLog.EventKey
        //responseLog.ExpirationDate
        //responseLog.Mantissa
        
        responseLog.Message = thisResponse.statusCode + ' ' + thisResponse.status;
        responseLog.Type='Response'; 
        responseLog.Content = 'LogX Processed: ' + JSON.serialize(thisResponse);
        
        return responseLog;
    }

}