/**
 * PeriodCloseTrigger — 3-line dispatcher; delegates to PeriodCloseTriggerHandler
 * via TriggerDispatcher (canonical Patrick Stephens framework). The dispatcher
 * applies any TriggerSetting__mdt-driven exclusions before invoking the
 * handler's phase methods.
 *
 * Subscribed to all DML phases so future rules don't require re-deploying the
 * trigger; the handler is no-op on any phase it doesn't override.
 */
trigger PeriodCloseTrigger on Period_Close__c (
    before insert, before update, before delete,
    after  insert, after  update, after  delete
) {
    TriggerDispatcher.run(new PeriodCloseTriggerHandler(), 'PeriodCloseTrigger');
}
