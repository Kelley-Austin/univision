public with sharing class LogEventTriggerHandler extends TriggerHandler {

    public override void afterInsert(Map<Id, sobject> logEventMap) {

        Map<String, Schema.SObjectField> logEventFieldsByName = Schema.SObjectType.LogEvent__e.fields.getMap();
        Map<String, Schema.SObjectField> logRecordingFieldsByName = Schema.SObjectType.Log__c.fields.getMap();
        Map<String, Schema.SObjectField> logDetailFieldsByName = Schema.SObjectType.LogDetail__c.fields.getMap();

        Map<String,Log__c> logRecordings = new Map<String,Log__c>();
        
        Map<String,List<LogDetail__c>> correlatedLogDetails = new Map<String,List<LogDetail__c>>();
        system.debug(LoggingLevel.INFO, '*****************************************');
        system.debug(LoggingLevel.INFO, 'LogEventTriggerHandler Events: ' + logEventMap.size());
        for(sObject logEvent : logEventMap.values()) {
            Log__c LogR = new Log__c();
            system.debug(LoggingLevel.INFO, ' CorrelationId: ' + logEvent.get('CorrelationId__c'));
            if(logEvent.get('CorrelationId__c')==null){
                logR.CorrelationId__c = LogX.getUuid().toString();
            } else {
                logR.CorrelationId__c = String.valueOf(logEvent.get('CorrelationId__c'));
            }
            if(logEvent.get('RunningUserID__c')==null){
                logR.RunningUserID__c = UserInfo.getUserId();
            } else {
                logR.RunningUserID__c = String.valueOf(logEvent.get('RunningUserID__c'));
            }
            logR.ReplayId__c = Decimal.valueof(String.valueOf(logEvent.get('ReplayId')));
            logR.EventUUid__c = String.valueOf(logEvent.get('EventUuid'));
            system.debug(LoggingLevel.INFO, 'ReplayId: ' + logR.ReplayId__c);
            system.debug(LoggingLevel.INFO, 'UUID: ' + logR.EventUuid__c);
            string runningUser = logR.RunningUserID__c; 
            if(logRecordings.containsKey(logR.CorrelationId__c)){
                //this correlation id is present in the same batch of logs
                system.debug(LoggingLevel.INFO, '  match on cId ' + logR.CorrelationId__c);
                LogDetail__c detail = new LogDetail__c();
                for(String fieldName : logEventFieldsByName.keySet()) {
                    if(logDetailFieldsByName.containsKey(fieldName)
                    && logDetailFieldsByName.get(fieldName).getDescribe().isUpdateable()) {
                        detail.put(fieldName,logEvent.get(fieldName));
                    }
                    detail.RunningUserID__c = runningUser;
                }
                if(!correlatedLogDetails.containsKey(logR.CorrelationId__c))
                    correlatedLogDetails.put(detail.CorrelationId__c,new List<LogDetail__c>());
                correlatedLogDetails.get(detail.CorrelationId__c).add(Detail);
                system.debug(LoggingLevel.INFO, ' LogDetail__c records: ' + correlatedLogDetails.get(detail.CorrelationId__c).size());
            } else {
                for(String fieldName : logEventFieldsByName.keySet()) {
                    if(logRecordingFieldsByName.containsKey(fieldName)
                    && logRecordingFieldsByName.get(fieldName).getDescribe().isUpdateable()) {
                        LogR.put(fieldName,logEvent.get(fieldName));
                    }
                    logR.RunningUserID__c = runningUser;
                }
                logRecordings.put(logR.CorrelationId__c,logR);
                system.debug(LoggingLevel.INFO, ' Log__c records:  ' + logRecordings.size());
            }
        }

        List<LogDetail__c> allDetails = new list<LogDetail__c>();
        //check for prexisting logs
        Map<String, Log__c> oldLogs = LogX.getLogs(logRecordings.keySet());
        system.debug(LoggingLevel.INFO, '  total pre-existing logs with matching CorrelationIds:  ' + oldLogs.size());
        if(oldLogs.size()>0){
            for(Log__c oldLog : oldLogs.values()){
                LogDetail__c detail = new LogDetail__c();
                for(String fieldName : logRecordingFieldsByName.keySet()) {
                    if(logDetailFieldsByName.containsKey(fieldName)
                    && logDetailFieldsByName.get(fieldName).getDescribe().isUpdateable()) {
                        detail.put(fieldName,logRecordings.get(oldLog.CorrelationId__c).get(fieldName));
                    }
                }
                if(!correlatedLogDetails.containsKey(detail.CorrelationId__c))
                    correlatedLogDetails.put(detail.CorrelationId__c,new List<LogDetail__c>());
                correlatedLogDetails.get(detail.CorrelationId__c).add(Detail);
                logRecordings.remove(oldLog.CorrelationId__c);
            }
        }
        if(logRecordings.size()>0){
            system.debug(LoggingLevel.INFO, 'BEGIN INSERT LOG RECORDS ' + logRecordings.size());
            insert logRecordings.values();
            system.debug(LoggingLevel.INFO, 'COMPLETE INSERT LOG RECORDS');
        }
        if(correlatedLogDetails.size()>0){
            //get already identfied correlated logs
            system.debug(LoggingLevel.INFO, '  correlatedLogDetails total parent logs:  ' + correlatedLogDetails.size());
            Map<String,Log__c> logs = LogX.getLogs(correlatedLogDetails.keySet());
            for(string parentCId : correlatedLogDetails.keySet()){
                Log__c lg = logs.get(parentCId);
                for(LogDetail__c detail : correlatedLogDetails.get(parentCId)){
                    detail.Log__c = lg.Id;
                    allDetails.add(detail);
                }
            }
            system.debug(LoggingLevel.INFO, 'BEGIN INSERT LOG DETAIL RECORDS ' + allDetails.size());
            Database.insert(allDetails, AccessLevel.SYSTEM_MODE);
            system.debug(LoggingLevel.INFO, 'COMPLETE INSERT LOG DETAIL RECORDS');
        }
        
        system.debug(LoggingLevel.INFO, '*****************************************');
    }
}