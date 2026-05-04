/**
 * Subscribes to Matrix_Order_Sync__e platform events and invokes
 * MatrixOrderSyncService to make the outbound REST callout to Matrix.
 *
 * Platform Event triggers run in their own asynchronous transaction after the
 * publishing transaction commits, so callouts are permitted here without any
 * additional queueable indirection.
 *
 * Governor limit note: Each Platform Event batch produces one trigger execution.
 * At the expected volume for an advertising ops team (a handful of status changes
 * per hour), one callout per event is well within the 100-callout-per-transaction
 * limit. If volume grows significantly, consider moving to a Queueable pattern.
 */
trigger MatrixOrderSyncTrigger on Matrix_Order_Sync__e (after insert) {
    for (Matrix_Order_Sync__e event : Trigger.new) {
        MatrixOrderSyncService.syncOpportunity(
            (Id) event.Opportunity_Id__c,
            event.Operation__c
        );
    }
}
