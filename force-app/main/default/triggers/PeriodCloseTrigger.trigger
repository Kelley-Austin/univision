/**
 * PeriodCloseTrigger — 3-line dispatcher; logic lives in
 * PeriodCloseTriggerHandler. We add before/after for all phases so future
 * rules don't require re-deploying the trigger. The handler is no-op on any
 * phase it doesn't override.
 */
trigger PeriodCloseTrigger on Period_Close__c (
    before insert, before update, before delete,
    after  insert, after  update, after  delete
) {
    new PeriodCloseTriggerHandler().run();
}
