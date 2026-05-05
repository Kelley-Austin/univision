/**
 * ActualRevenueTrigger — 3-line dispatcher; logic lives in
 * ActualRevenueTriggerHandler. See that class for what each phase does.
 *
 * If you find yourself wanting to add logic here, push it down into a
 * phase method on the handler instead. Triggers stay thin so we have one
 * place to look for behavior.
 */
trigger ActualRevenueTrigger on Actual_Revenue__c (
    before insert, before update, before delete,
    after  insert, after  update, after  delete, after undelete
) {
    new ActualRevenueTriggerHandler().run();
}
