global without sharing class LogFlow {
    @InvocableMethod(label='Log Events')
    global static List<LogRequest> LogEvents(List<LogRequest> requests) {
        List<Log> logs = new List<Log>();
        for(LogRequest request: requests){
            Log lg = LogX.logEvent(request.logEventName, request.type, request.message, request.eventKey, request.content, request.correlationId, false, true);
            lg.ObjectReferenceId = request.objectReferenceId;
            lg.ExpirationDate = request.expirationDate;
            lg.Mantissa = request.mantissa;
            logs.add(lg);
        }
        try{
            List<Database.SaveResult> results = Log.emitLogsWithResults(logs, true);
            Integer i=0;
            while(i<results.size()){
                if(!results[i].isSuccess()){
                    requests[i].isSuccess = false;
                    requests[i].errorMessage = results[i].getErrors()[0].getMessage();
                } else {
                    requests[i].isSuccess=true;
                }
                i++;
            }
        } catch(Exception exc){
            for(LogRequest request : requests){
                request.isSuccess = false;
                request.errorMessage = exc.getMessage();
            }
        }
        return requests;
    }

    global class LogRequest {
        @InvocableVariable(label='LogEvent Name' required=true)
        global String logEventName;

        @InvocableVariable(label='Type' required=true)
        global String type;

        @InvocableVariable(label='CorrelationId')
        global String correlationId;

        @InvocableVariable(label='Message')
        global String message;

        @InvocableVariable(label='Content')
        global String content;

        @InvocableVariable(label='EventKey')
        global String eventKey;

        @InvocableVariable(label='ObjectReferenceId')
        global Id objectReferenceId;

        @InvocableVariable(label='Expiration Date')
        global Date expirationDate;

        @InvocableVariable(label='Mantissa')
        global Decimal mantissa;

        @InvocableVariable(label='IsSuccess')
        global Boolean isSuccess;

        @InvocableVariable(label='Error Message')
        global String errorMessage;
    }
}