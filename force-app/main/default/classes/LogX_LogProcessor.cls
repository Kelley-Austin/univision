public without sharing class LogX_LogProcessor extends LogProcessor implements ILogProcessor{

    public override LogProcessor.Result processLogs(){

        List<Log> resultLogs = new List<Log>();

        for(Log lg:logs){
                Log lgx = processLog(lg);
                resultLogs.add(lgx);
        }

        LogProcessor.Result result = new LogProcessor.Result(resultLogs);
        return result;
    }

    public override Log processLog(Log lg){
        Log resultLog = null;
        switch on lg.Type {
            when 'Callout' {             
                try{ 
                    //Make Callout
                    RESTHandler testRestHandler = new RESTHandler(lg);
                    RESTHandler.Response resp = testRestHandler.wrapCallout();
                    //Do any immediate response processing
                    String processedBody = processBody(resp);
                    resultLog = LogX.logEvent('LogX_LogEvent', 'Response', resp.statusCode + ' ' + resp.status , null, processedBody, lg.correlationId);
                } catch(Exception e){
                    return LogX.logException(e, 'LopgX Callout Failed', lg.CorrelationId);
                }
            } when 'LogThenCallout'{
                resultLog = LogX.logEvent('LogX_LogEvent', 'Callout', 'Logged. Enqueue Callout', null, null, lg.correlationId);
            } when 'Response' {
                resultLog = LogX.logEvent('LogX_LogEvent', 'Finalized', 'Processing complete', null, 'content',lg.correlationId);
            } when else {
                return null;
            }
        }
        return resultLog;
    }

    private String processBody(RESTHandler.Response resp){
        return 'Processed:: \n' + resp.body;
    }

}