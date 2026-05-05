trigger ProjectionTrigger on Projection__c (before insert, before update, after update) {
    if (Trigger.isBefore) {
        ProjectionTriggerHandler.handleBefore(Trigger.new, (Map<Id, Projection__c>) Trigger.oldMap);
    } else if (Trigger.isAfter && Trigger.isUpdate) {
        ProjectionTriggerHandler.handleAfterUpdate(Trigger.new, (Map<Id, Projection__c>) Trigger.oldMap);
    }
}
