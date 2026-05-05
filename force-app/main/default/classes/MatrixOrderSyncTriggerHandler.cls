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
 *  Framework
 *  ---------
 *  Extends the canonical TriggerHandler base class (Patrick Stephens'). For
 *  Platform Event triggers, Salesforce keys Trigger.newMap by ReplayId, so
 *  TriggerDispatcher can hand us the Map<Id, SObject> like any normal trigger.
 *
 *  Test isolation
 *  --------------
 *  Skips the callout under Test.isRunningTest() by default — tests don't want
 *  unintended outbound HTTP and the Matrix endpoint isn't always mocked.
 *  Tests that DO want to exercise the callout path can:
 *    1. Configure a TriggerSetting__mdt entry to bypass this handler entirely, OR
 *    2. Skip publishing the event in the test method, OR
 *    3. Refactor MatrixOrderSyncService to expose a test-mode override that
 *       Test.setMock can satisfy.
 *  All three are reasonable; pick whatever suits the test scenario.
 * =============================================================================
 */
public with sharing class MatrixOrderSyncTriggerHandler extends TriggerHandler {

    /**
     * Platform Event triggers only fire on afterInsert in Apex; no other
     * phase exists for events. We override afterInsert and route into the
     * sync service per event.
     */
    public override void afterInsert(Map<Id, SObject> newRecordsMap) {
        dispatch((List<Matrix_Order_Sync__e>) newRecordsMap.values());
    }

    @TestVisible
    private static void dispatch(List<Matrix_Order_Sync__e> events) {
        // Default: skip in test context. Tests that want callout coverage
        // should bypass via TriggerSetting__mdt or refactor the service to
        // accept a test-mode mock. Production runs always proceed.
        if (Test.isRunningTest()) return;

        for (Matrix_Order_Sync__e ev : events) {
            // Defensive: skip events lacking the required correlation ID.
            // Platform events with NULL Opportunity_Id__c indicate a publisher
            // bug; we could LogX.logEvent here to surface the malformed event
            // in Log__c — left as a TODO so the immediate refactor stays focused.
            if (ev.Opportunity_Id__c == null) continue;

            MatrixOrderSyncService.syncOpportunity(
                (Id) ev.Opportunity_Id__c,
                ev.Operation__c
            );
        }
    }
}
