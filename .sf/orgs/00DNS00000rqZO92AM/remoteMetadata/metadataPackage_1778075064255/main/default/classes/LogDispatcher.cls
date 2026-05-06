//new version
public without sharing class LogDispatcher extends TriggerHandler implements Queueable, Database.AllowsCallouts{
    
    public Map<String,List<Log>> handlerMap {get;set;}
    public Map<String,List<Log>> handlerMapControlledQueue {get;set;}

    public LogDispatcher(){
        this(new Map<String,List<Log>>());
    }
    
    public LogDispatcher(Map<String,List<Log>> handlerMap) {
        this.handlerMap = handlerMap;
    }
    public override void beforeInsert(List<sObject> newRecords) {
        //check if Quiddity is populated, if not fill n the context variables
        for(sObject lg : newRecords){
            if(lg.get('Quiddity__c')==null){
                lg.put('Quiddity__c',Request.getCurrent().getQuiddity().toString() + ' Direct record creation');
                lg.put('RunningUserId__c',UserInfo.getUserId());
                lg.put('RunningUserName__c', UserInfo.getName());
                lg.put('IsBatch__c', System.isBatch());
                lg.put('IsFuture__c', System.isFuture());
                lg.put('IsQueueable__c', System.isQueueable());
                lg.put('IsScheduled__c', System.isScheduled());
                lg.put('composedDateTime__c', System.now());
                if(Trigger.isExecuting){
                    lg.put('IsTrigger__c',true);
                    lg.put('TriggerContext__c', String.valueOf(Trigger.operationType));
                    lg.put('TriggerSize__c', Trigger.size);
                }
            }
            if(lg.get('CorrelationID__c')==null){
                lg.put('CorrelationID__c', LogX.getUUID().toString());
            } 
        }
    }

    //Stubs for potential future use
    // public override void beforeUpdate(Map<Id, sObject> newRecordsMap ,Map<Id, sObject> oldRecordsMap) {}
    // public override void afterUpdate(Map<Id, sObject> newRecordsMap,Map<Id, sObject> oldRecordsMap) {}
    // public override void beforeDelete(Map<Id, sObject> oldRecordsMap) {}
    // public override void afterDelete(Map<Id, sObject> oldRecordsMap) {}
    // public override void afterUnDelete(Map<Id, sObject> oldRecordsMap) {}

    public override void afterInsert(Map<Id, sObject> newRecordsMap) {
        Map<String,SObject> newMap = new Map<String,SObject>(newRecordsMap.values());
        for(Id key : newRecordsMap.keySet()){
            newMap.put(String.valueOf(key),newRecordsMap.get(key));
        }
        handleAfterInsert(newMap);
    }

    public void handleAfterInsert(Map<String, sObject> newRecordsMap) {
        List<String> processList = new List<String>();
        Map<String,LogXEventHandlers__mdt> handlerMatchMap = new Map<String,LogXEventHandlers__mdt>();
        for(LogXEventHandlers__mdt ph : LogX.LogProcessHandlers){
            String handlerMatch = ph.EventName__c+ph.Type__c;
            handlerMatchMap.put(handlerMatch,ph);
        }
        for(sObject obj : newRecordsMap.values()){
            try{
                String logEventName = (String)obj.get('LogEventName__c');
                String logType = (String)obj.get('Type__c');
                String pl = '[' + obj.Id + ' objType: ' + obj.getSObjectType() + ' LogEventName: ' + logEventName + ' CorrelationId: ' + (String)obj.get('CorrelationID__c') + ' LogType: ' + logType + ' || Handler: ';
               
                //check metadata
                //get the handlers and check to see if the handler is a match for this record
                //if it is, add it to the list of records to process for that handler
                if(handlerMatchMap.containsKey(logEventName+'all') || handlerMatchMap.containsKey('all'+logType) || handlerMatchMap.containsKey(logEventName+logType)){
                    //this is a match
                    Log lg = Log.toLog(obj);
                    if(handlerMatchMap.containsKey(logEventName+'all')){
                        String handlerText = handlerMatchMap.get(logEventName+'all').Handler__c;
                        if(handlerMatchMap.get(logEventName+'all').Invoke__c=='Flow'){
                            handlerText = 'FLOW:'+handlerText;
                        }
                        if(handlerMatchMap.get(logEventName+'all').ControlQueueing__c==true){
                            handlerText = 'CQX:'+handlerText;
                        }
                        if(!handlerMap.containsKey(handlerText)){
                            handlerMap.put(handlerText, new List<Log>{lg});
                        } else {
                            handlerMap.get(handlerText).add(lg);
                        }
                        pl += ' ' + handlerText;
                    }
                    if(handlerMatchMap.containsKey('all'+logType) || Test.IsRunningTest()){
                        String handlerText = handlerMatchMap.get('all'+logType).Handler__c;
                        if(handlerMatchMap.get('all'+logType).Invoke__c=='Flow'){
                            handlerText = 'FLOW:'+handlerText;
                        }
                        if(handlerMatchMap.get('all'+logType).ControlQueueing__c==true){
                            handlerText = 'CQX:'+handlerText;
                        }
                        if(!handlerMap.containsKey(handlerText)){
                            handlerMap.put(handlerText, new List<Log>{lg});
                        } else {
                            handlerMap.get(handlerText).add(lg);
                        }
                        pl += ' ' + handlerText;
                    }
                    if(handlerMatchMap.containsKey(logEventName+logType)){
                        String handlerText = handlerMatchMap.get(logEventName+logType).Handler__c;
                        if(handlerMatchMap.get(logEventName+logType).Invoke__c=='Flow'){
                            handlerText = 'FLOW:'+handlerText;
                        }
                        if(handlerMatchMap.get(logEventName+logType).ControlQueueing__c==true){
                            handlerText = 'CQX:'+handlerText;
                        }
                        if(!handlerMap.containsKey(handlerText)){
                            handlerMap.put(handlerText, new List<Log>{lg});
                        } else {
                            handlerMap.get(handlerText).add(lg);
                        }
                        pl += ' ' + handlerText;
                    }
                } 
                pl+=']\n';
                processList.add(pl);
            } catch (Exception ex){
                LogX.logException(ex, 'Error Handling in LogDispatch After Insert', String.valueOf(obj.get('CorrelationID__c')),true);
            }
        }
        LogX.debug('LogDispatcher processList ' + newRecordsMap.values()[0].getSObjectType() + ' ' + newRecordsMap.size() + ':\n' + processList.toString());

        if(handlerMap.size()>50){
            String content = '';
            for(String handler:handlerMap.keySet()){
                content += handler + ': ' + handlerMap.get(handler).size() + '\n';
            }
            LogX.logEvent('Exception', 'HandlerProcessLimitExceeded', 'You cannot process more than 50 distinct LogProcessor handlers in a single invocation. You attempted: ' + handlerMap.size() + '.' , null, content, null, true,true);
        } else {
            //enqueue the handlers as individual jobs
            for(String handler:handlerMap.keySet()){
                Map<String,List<Log>> newProcessMap = new Map<String,List<Log>>();
                if(!handler.startsWith('CQX:')){
                    //this handler will not control its own queueing
                    newProcessMap.put(handler,handlerMap.get(handler));
                    handlerMap.remove(handler);
                    LogX.enqueueJob(new LogDispatcher(newProcessMap));
                }
            }
            processLogs();
        }
    }

    public void execute(QueueableContext context) {
        processLogs();
    }

    public void processLogs(){
        for(String handler:handlerMap.keySet()){
            system.debug(LoggingLevel.INFO, '^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
            System.debug(LoggingLevel.INFO, 'Begin processing for Handler ' + handler);
            system.debug(LoggingLevel.INFO, '^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
            try{
                if(handler.startsWith('FLOW:')){
                    //we have a flow
                    Map<String,Object> inputs = New Map<String,Object>();
                    for(Log lg:handlerMap.get(handler)){
                        inputs.put(lg.correlationId, lg);
                    }
                    String flowName = handler.replace('FLOW:','');
                    Flow.Interview thisFlow = Flow.Interview.createInterview(flowName, inputs);
                    thisFlow.start();
                    //Todo: post processing for flows like finalization for the apex classes?
                } else {
                    String HandlerType = handler.replace('CQX:','');
                    if(handler.startsWith('LogX_LogProcessor'))
                        HandlerType = 'LogX_LogProcessor';
                    Type t = Type.forName(HandlerType);
                    system.debug(LoggingLevel.INFO, '^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
                    System.debug(LoggingLevel.INFO, 'Instantiate type for ' + String.valueOf(t));
                    system.debug(LoggingLevel.INFO, '^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
                    LogProcessor lp = (LogProcessor)t.newInstance();
                    lp.setLogs(handlerMap.get(handler));
                    system.debug(LoggingLevel.INFO, '^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
                    System.debug(LoggingLevel.INFO, 'Begin processing for Handler ' + Handler);
                    system.debug(LoggingLevel.INFO, '^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
                    LogProcessor.Result res = lp.processLogs();
                    system.debug(LoggingLevel.INFO, '^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
                    System.debug(LoggingLevel.INFO, 'Processing result for Handler ' + Handler);
                    system.debug(LoggingLevel.INFO, '^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
                    res.finalize();
                    system.debug(LoggingLevel.INFO, '^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
                    System.debug(LoggingLevel.INFO, 'Finalization complete for Handler ' + Handler);
                    system.debug(LoggingLevel.INFO, '^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
                }
            } catch (Exception ex){
                logX.logException(ex, 'LogDispatcher error executing handler. ' + handler + ' run was not completed.');
            }
        }
    }
}