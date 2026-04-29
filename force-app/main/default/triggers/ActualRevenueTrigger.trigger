trigger ActualRevenueTrigger on Actual_Revenue__c (before insert, before update) {
    ActualRevenueTriggerHandler.handle(Trigger.new, Trigger.oldMap, Trigger.isInsert);
}
