trigger ProjectionTrigger on Projection__c (before insert, before update) {
    ProjectionTriggerHandler.handle(Trigger.new);
}
