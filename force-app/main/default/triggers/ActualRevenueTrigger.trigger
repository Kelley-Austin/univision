/**
 * ActualRevenueTrigger — 3-line dispatcher; delegates to
 * ActualRevenueTriggerHandler via TriggerDispatcher (canonical Patrick
 * Stephens framework). Subscribed to all DML phases so future rules can
 * be added in the handler without re-deploying this trigger.
 */
trigger ActualRevenueTrigger on Actual_Revenue__c (
    before insert, before update, before delete,
    after  insert, after  update, after  delete, after undelete
) {
    TriggerDispatcher.run(new ActualRevenueTriggerHandler(), 'ActualRevenueTrigger');
}
