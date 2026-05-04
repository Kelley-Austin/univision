trigger PeriodCloseTrigger on Period_Close__c (before update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        PeriodCloseTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
