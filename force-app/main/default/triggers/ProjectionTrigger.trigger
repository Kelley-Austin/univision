/**
 * ProjectionTrigger — 3-line dispatcher; delegates to ProjectionTriggerHandler
 * via TriggerDispatcher (canonical Patrick Stephens framework). Subscribed to
 * all DML phases so future rules can be added in the handler without
 * re-deploying this trigger.
 */
trigger ProjectionTrigger on Projection__c (
    before insert, before update, before delete,
    after  insert, after  update, after  delete
) {
    TriggerDispatcher.run(new ProjectionTriggerHandler(), 'ProjectionTrigger');
}
