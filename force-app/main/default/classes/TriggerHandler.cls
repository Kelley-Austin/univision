/**
 * This virtual class serves as a generic Trigger Handler allowing derived classes
 * to implement custom logic for different phases of the trigger lifecycle.
 * 
 * Use this class by extending it and overriding only the methods you need
 * for your specific trigger requirements.
 * 
 * Triggers you extend with this class and register in tyhe TriggerHandler metadata 
 * can by run by the triggerDispatcher, applying bypasss logic 
 * 
 * @author Patrick Stephens
 * @version 1.0 
 */
public virtual class TriggerHandler {

    public virtual void beforeInsert(List<SObject> newRecords){
        if(newRecords != null) {
            System.debug(LoggingLevel.INFO, 'TriggerHandler beforeInsert records: ' + newRecords.size());
        }
    }

    
    public virtual void afterInsert(Map<Id, SObject> newRecordsMap){
        if(newRecordsMap != null) {
            System.debug(LoggingLevel.INFO, 'TriggerHandler afterInsert records: ' + newRecordsMap.size());
        }
    }

    
    public virtual void beforeUpdate(Map<Id, SObject> newRecordsMap, Map<Id, sObject> oldRecordsMap){
        if(newRecordsMap != null) {
            System.debug(LoggingLevel.INFO, 'TriggerHandler beforeUpdate records: ' + newRecordsMap.size());
        }
    }

    
    public virtual void afterUpdate(Map<Id, SObject> newRecordsMap, Map<Id, sObject> oldRecordsMap){
        if(newRecordsMap != null) {
            System.debug(LoggingLevel.INFO, 'TriggerHandler afterUpdate records: ' + newRecordsMap.size());
        }
    }

   
    public virtual void beforeDelete(Map<Id, SObject> oldRecordsMap){
        if(oldRecordsMap != null) {
            System.debug(LoggingLevel.INFO, 'TriggerHandler beforeDelete records: ' + oldRecordsMap.size());
        }
    }

    
    public virtual void afterDelete(Map<Id, SObject> oldRecordsMap){
        if(oldRecordsMap != null) {
            System.debug(LoggingLevel.INFO, 'TriggerHandler afterDelete records: ' + oldRecordsMap.size());
        }
    }
    
    public virtual void afterUnDelete(Map<Id, SObject> newRecordsMap){
        if(newRecordsMap != null) {
            System.debug(LoggingLevel.INFO, 'TriggerHandler afterUnDelete records: ' + newRecordsMap.size());
        }
    }
}