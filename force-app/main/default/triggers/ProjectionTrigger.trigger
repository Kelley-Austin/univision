/**
 * ProjectionTrigger — 3-line dispatcher; logic lives in
 * ProjectionTriggerHandler. Subscribed to all DML phases so future rules
 * (e.g. afterInsert audit, beforeDelete guard) can be added in the handler
 * without re-deploying this trigger.
 */
trigger ProjectionTrigger on Projection__c (
    before insert, before update, before delete,
    after  insert, after  update, after  delete
) {
    new ProjectionTriggerHandler().run();
}
