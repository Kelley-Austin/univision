public without sharing class Log {
    
    //Static initializer
    {
        this.RunningUserId = UserInfo.getUserId();
        this.RunningUserName = UserInfo.getName();
        this.IsBatch = System.isBatch();
        this.IsFuture = System.isFuture();
        this.IsQueueable = System.isQueueable();
        this.IsScheduled = System.isScheduled();
        this.composedDateTime = System.now();
        this.quiddity = Request.getCurrent().getQuiddity().toString();
        if(Trigger.isExecuting){
            this.IsTrigger = true;
            this.TriggerContext = String.valueOf(Trigger.operationType);
            this.TriggerSize = Trigger.size;
        }
    }

    public Decimal Ordinal{
        get{
            if(Ordinal==null) 
                ordinal = cache.getIterator(this.CorrelationId);
            return ordinal;
        } set;
    }


    public String CorrelationId {
        get {
            if(String.isBlank(CorrelationId)){
                correlationId = logX.getUuid().toString();
            }
            return correlationId;
        } set{
            correlationId = value;
        }

    } 
    public String Message {get; set{
        message = trunc(value,255);
    }}

    public Id ObjectReferenceId {get; set;}
    public String LogEventName {get; set{
        logEventName = trunc(value,255);
    }}
    public String Content {get; set{ 
        content = trunc(value,131072);
    }}
    public String Type {get; set{
        type = trunc(value,255);
    }}
    public String EventKey {get; set{
        eventKey = trunc(value,255);
    }}
    //User Info
    public Id RunningUserId {get;private set;}
    public String RunningUserName {get;private set;}
    // Trigger info
    public String  TriggerContext {get;private set;}
    public Decimal TriggerSize {get;private set;}
    public Boolean IsTrigger {get;private set;}
    // System info
    public Boolean IsScheduled {get;private set;}
    public Boolean IsQueueable {get;private set;}
    public Boolean IsFuture {get;private set;}
    public Boolean IsBatch {get;private set;}
    public Datetime ComposedDateTime {get;private set;}
    public String Quiddity {get;set;}
    public Date ExpirationDate {get;set;}
    public Double Mantissa {get;set;}
    public Integer ReplayId {get;private set;}
    public String EventUuid  {get;private set;}

    // ** Constructors
    public Log(){
        initializeLog(null, null, null, null, null, null);
    }
    public Log(String eventName, String message, String correlationId){
        initializeLog(eventName, null, message, null, null, correlationId);
    }
    public Log(String eventName, String message, String content, String correlationId){
        initializeLog(eventName, null, message, null, content, correlationId);
    }
    public Log(String eventName, String message, String eventKey, String content, String correlationId){
        initializeLog(eventName, null, message, eventKey, content, correlationId);
    }
    public Log(String eventName, String type, String message, String eventKey, String content, String correlationId){
        initializeLog(eventName, type, message, eventKey, content, correlationId);
    }

    public void cacheEventKey(){
        Cache.put(this.eventKey, System.now());
    }

    public void cacheEventKey(Integer ttl){
        Cache.put(this.eventKey, System.now(), ttl);
    }

    public void clearCachedEventKey(){
        Cache.Org.remove(this.eventKey);
    }

    private void initializeLog(String eventName, String type, String message, String eventKey, String content, String correlationId){
        this.logEventName = eventName;
        this.type = type;
        this.message = message;
        this.eventKey = eventKey;
        this.content = content;
        this.correlationId = correlationId;
        if(this.logEventName!='Debug'){
            if(this.logEventName=='Exception'){
                LogX.debug('*******\nNew Exception Log Constructed.\n' + 'CorrelationId: ' + this.correlationId + '\n*******\n' + content,this);
            } else if(!(this.logEventName==null&&this.message==null&&this.type==null)) {
                LogX.debug('*******\nNew Log Constructed.\n' + 'CorrelationId: ' + this.correlationId + '\n*******\n' + message,this);
            }
        }
        

    }

    //** Static Methods
    private String trunc(String value, Integer width){
        if(String.isNotBlank(value) && value.length()>3 && value.length()>width){
            return value.abbreviate(width);
        } else {
            return value;
        }
    }

    public static Log toLog(Object obj){
            if(obj instanceof Log){
                return (Log)obj;        
            } else if(obj instanceof Log__c){
                return Log.toLog((Log__c)obj);
            } else if(obj instanceof LogDetail__c){
                return Log.toLog((LogDetail__c)obj);
            } else {
                return new Log(null,null,null);
            }

    }

    public static List<Log> toLogs(List<Object> objs){
        List<Log> logs = new List<Log>();
        for(object obj:objs){
            if(obj instanceof Log){
                logs.add((Log)obj);        
            } else if(obj instanceof Log__c){
                logs.add(Log.toLog((Log__c)obj));  
            } else if(obj instanceof LogDetail__c){
                logs.add(Log.toLog((LogDetail__c)obj));  
            } 
        }
        return logs;
    }

    public String getStr(String propertyName){
        Object obj = this.get(propertyName);
        if(obj!=null){
            return JSON.serialize(obj);
        }
        return null;
    }

    public Object get(String propertyName){
        String jStr = JSON.serialize(this);
        Map<String,object> deSerializedObj = (Map<String,object>)JSON.deserializeUntyped(jStr);
        if(deSerializedObj.keySet().contains(propertyName)){
            return deSerializedObj.get(propertyName);
        }
        return null;
    }

    public static Log toLog(Map<String, Object> propertyMap){
        Map<String,Object> newMap = new Map<String,Object>();
        for(String propertyName:propertyMap.keySet()){
            if(propertyName.endsWith('__c')){
                newMap.put(propertyName.Replace('__c',''), propertyMap.get(propertyName));
            }
        }
        String serialized = JSON.serialize(newMap);
        return (Log)JSON.deserialize(serialized,Log.class);
    }

    public static Log toLog(Log__c log){
        return toLog(log.getPopulatedFieldsAsMap());
    }

    public static Log toLog(LogDetail__c logDetail){
        return toLog(logDetail.getPopulatedFieldsAsMap());
    }

    public static List<Log> toLogs(List<Log__c> logs){
        List<Log> newLogs = new List<Log>();
        for(Log__c logDetail : logs){
            newLogs.add(toLog(logDetail));
        }
        return newLogs;
    }
    public static List<Log> toLogs(List<LogDetail__c> logDetails){
        List<Log> newLogs = new List<Log>();
        for(LogDetail__c log : logDetails){
            newLogs.add(toLog(log));
        }
        return newLogs;
    }
    public static Map<String, List<Log>> toLogMap(List<Log> logs){
        Map<String, List<Log>> logMap = new Map<String, List<Log>>();
        for(Log lg : logs){
            if(!logMap.containsKey(lg.correlationId)){
                logMap.put(lg.logEventName, new List<Log>());
            }
            logMap.get(lg.correlationId).add(lg);
        }
        return logMap;
    }

    public ImLogEvent__e createImLogEvent() {
        Map<String,Object> genericLog = (Map<String, Object>)JSON.deserializeUntyped(JSON.serialize(this));
        ImLogEvent__e logE = (ImLogEvent__e)ImLogEvent__e.sObjectType.newSObject(null, true);
        this.EventUUID = logE.EventUuid;
        Map<String,Object> newLog = new Map<String,Object>();
        for(String property:genericLog.keySet()){
            if(property!='EventUuid' && property!='ReplayId'){
                newLog.put(property+'__c', genericLog.get(property));
            } 
        }
        LogX.setSobject(logE, newLog);
        return logE;
    }

    public LogEvent__e createLogEvent() {
        Map<String,Object> genericLog = (Map<String, Object>)JSON.deserializeUntyped(JSON.serialize(this));
        LogEvent__e logE = (LogEvent__e)LogEvent__e.sObjectType.newSObject(null, true);
        this.EventUUID = logE.EventUuid;
        Map<String,Object> newLog = new Map<String,Object>();
        for(String property:genericLog.keySet()){
            if(property!='EventUuid' && property!='ReplayId'){
                newLog.put(property+'__c', genericLog.get(property));
            }
        }
        LogX.setSobject(logE, newLog);
        return logE;
    }


    // ** Emit Methods 
    public void emit(){
        Log.emit(this);
    }
    public void emitIm(){
        Log.emitIm(this);
    }
    public static void emit(Log lg){
        List<Log> logs = new List<Log>();
        logs.add(lg);
        Log.emitLogs(logs,false);
    }
    public static void emitIM(Log lg){
        List<Log> logs = new List<Log>();
        logs.add(lg);
        Log.emitLogs(logs, true);
    }
    public static void emit(List<Log> logs) {
        Log.emitLogs(logs,false);
    }
    public static void emitIM(List<Log> logs) {
        Log.emitLogs(logs,true);
    }

    public static List<Database.SaveResult> emitLogsWithResults(List<Log> logs, Boolean emitImmediately) {
        Map<string,Log> retryMap = new Map<String,Log>();
        LogEventCallback logEventCallback = new LogEventCallback(retryMap);
        List<LogEvent__e> logEvents = new List<LogEvent__e>();
        List<IMLogEvent__e> IMlogEvents = new List<IMLogEvent__e>();
        for(Log lg : logs){
            if(lg!=null){
                retryMap.put(lg.EventUUID,lg);
                if(emitImmediately){
                    IMlogEvents.add(lg.createImLogEvent());
                } else {
                    logEvents.add(lg.createLogEvent());
                }
            }
        }
        if(logEvents.size()>0){
            System.debug(LoggingLevel.INFO,'Emit Request for ' + logEvents.size());
            List<Database.SaveResult> result = Eventbus.publish(logEvents, logEventCallback);
            logX.debug('Published Log Events Total: ' + result.size() + ' logs.',result);
            return result;
        }
        if(IMlogEvents.size()>0){
            System.debug(LoggingLevel.INFO,'Emit Immediate Request for ' + IMlogEvents.size());
            List<Database.SaveResult> result = Eventbus.publish(IMlogEvents, logEventCallback);
            logX.debug('Published Log Events Immediately Total: ' + result.size() + ' logs.',result);
            return result;
        }
        return null;
    }

    public static void emitLogs(List<Log> logs, Boolean emitImmediately) { 
        emitLogsWithResults(logs, emitImmediately);
    }

    
    

    //Callback class
    //We do not track success due to volume considerations. Most publish events succeed.
    public class LogEventCallback implements EventBus.EventPublishFailureCallback {
        public final Integer MAX_RETRIES = logX.getParamInt('PublishRetries');
        private Map<String,Log> retryMap {get;set;}
        private Integer retryCounter = 0;

        public LogEventCallback(Map<String,Log> retryMap){
            this.retryMap = retryMap;
        }

        public void onFailure(EventBus.FailureResult result) {
            // Get event UUIDs from the result
            List<String> eventUuids = result.getEventUuids();
            LogX.debug('Failed to publish events', eventUuids);

            if (retryCounter < MAX_RETRIES) {
                // Try to re-publish the failed events          
                Map<String,Log> newRetryMap = new Map<String,Log>();
                List<IMLogEvent__e> logEvents = new List<IMLogEvent__e>();
                for (String uuid : retryMap.keySet()) {
                    // Create a new event with the contents of the failed event
                    IMLogEvent__e logE = retryMap.get(uuid).createIMLogEvent();
                    logEvents.add(logE);
                    // Use a new map since the new event will have a different uuid
                    newRetryMap.put(logE.EventUuid, retryMap.get(uuid));
                }
                // Replace old uuid map because we no longer need its contents
                retryMap = newRetryMap;
                
                // Republish with the same callback passed in again as 'this'
                List<Database.SaveResult> retryResult = EventBus.publish(logEvents, this); 
                logX.debug('Published Log Events Total: ' + retryResult.size() + ' logs.',retryResult);
                
                // Increase counter
                retryCounter++;
            } else {
                // Retry exhausted, attempt to log exceptions instead
                LogX.debug('Failed to publish events Error handler', eventUuids);
                LogX.LogXException exc = new LogX.LogXException('Publish retries exceeded');
                LogX.logException(exc, 'Failed to publish LogEvents after ' + retryCounter + ' attempts.', null, true);
                List<Log> exLogs = new List<Log>();
                for(String uuid:retryMap.keySet()){
                    Log lg = LogX.logException(exc, 'Failed to publish LogEvent after ' + retryCounter + ' attempts.', retryMap.get(uuid).CorrelationId);
                    exLogs.add(lg);
                }
                Log.emitLogs(exLogs,true);
            }
        }        
    }
}