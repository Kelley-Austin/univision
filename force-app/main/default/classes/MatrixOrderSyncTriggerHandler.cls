/**
 * =============================================================================
 *  MatrixOrderSyncTriggerHandler
 * =============================================================================
 *
 *  Purpose
 *  -------
 *  Subscribes to the Matrix_Order_Sync__e platform event and invokes
 *  MatrixOrderSyncService.syncOpportunity to make the outbound REST callout
 *  to Matrix.
 *
 *  Why a Platform Event (vs. an Apex trigger on Opportunity)
 *  ---------------------------------------------------------
 *  Platform Event triggers run in their own asynchronous transaction AFTER
 *  the publishing transaction commits. That means:
 *    * Outbound HTTP callouts are permitted directly in the trigger (no
 *      Queueable indirection needed) — DML and callout aren't combined in
 *      the same transaction.
 *    * If the publishing DML rolls back, no events are delivered, so we
 *      never call out for state that doesn't actually exist.
 *
 *  Volume note
 *  -----------
 *  Each Platform Event batch produces ONE trigger execution (Salesforce
 *  groups events for delivery). At the expected volume for an advertising
 *  ops team — single-digit status changes per hour — the per-transaction
 *  callout limit (100) is not a concern. If the volume ever climbs into
 *  hundreds-per-hour territory, move the callout into a Queueable and
 *  use the trigger only to enqueue.
 *
 *  Test seam
 *  ---------
 *  Honor TestSettings.enableCalloutsInTests: when false (default) we skip
 *  the syncOpportunity call entirely under test. Existing tests that mock
 *  the callout flip the flag inside the test method.
 * =============================================================================
 */
public with sharing class MatrixOrderSyncTriggerHandler extends TriggerHandler {

    /**
     * Platform Event triggers only fire on afterInsert in Apex; no other
     * phase exists for events. We override afterInsert and route into the
     * sync service per event.
     */
    protected override void afterInsert() {
        dispatch((List<Matrix_Order_Sync__e>) Trigger.new);
    }

    @TestVisible
    private static void dispatch(List<Matrix_Order_Sync__e> events) {
        // In test context, only honor the call when the test has explicitly
        // opted in via TestSettings.enableCalloutsInTests + Test.setMock.
        if (Test.isRunningTest() && !TestSettings.enableCalloutsInTests) return;

        for (Matrix_Order_Sync__e ev : events) {
            // Defensive: skip events lacking the required correlation ID.
            // Platform events with NULL Opportunity_Id__c indicate a publisher
            // bug — log via Logger once that framework lands; for now, skip.
            if (ev.Opportunity_Id__c == null) continue;

            MatrixOrderSyncService.syncOpportunity(
                (Id) ev.Opportunity_Id__c,
                ev.Operation__c
            );
        }
    }
}
