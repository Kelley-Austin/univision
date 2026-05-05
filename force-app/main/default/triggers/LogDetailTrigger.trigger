trigger LogDetailTrigger on LogDetail__c (before insert, after insert, before update, after update, before delete, after delete, after unDelete) {
    TriggerDispatcher.run(new LogDispatcher(), 'LogDispatcher');
}