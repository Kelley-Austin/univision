/**
 * =============================================================================
 *  ProjectionTriggerHandler — Projection__c lifecycle behavior
 * =============================================================================
 *
 *  Phases
 *  ------
 *  beforeInsert / beforeUpdate
 *      * Build / refresh Composite_Key__c from the dimension fields. The key
 *        format ("Account|Category|RevenueType|Year|Month") is shared with
 *        ProjectionRollupQueueable and Reconciliation logic — see
 *        buildCompositeKey() docstring. Must be set before save so unique
 *        constraints + downstream lookups work in the same transaction.
 *      * On update only: block illegal forecast-stage regression unless the
 *        running user holds the System_Budget_Lock_Bypass custom permission.
 *
 *  afterUpdate
 *      * For any row whose Forecast_Stage__c changed, publish a
 *        Forecast_Stage_Changed__e platform event so subscribers (snapshot
 *        scheduler, audit log, etc.) can react asynchronously.
 *
 *  Forecast stage rank
 *  -------------------
 *  Stages 0–5 then Booked form a strict ascending order. NA is intentionally
 *  outside the order: any stage may move to or from NA freely (e.g. a user
 *  marks an opportunity Not Applicable, or an integration retroactively
 *  classifies an old NA row). The map's keys are the picklist values — keep
 *  them in sync if the picklist changes.
 *
 *  Bypass permission
 *  -----------------
 *  System_Budget_Lock_Bypass is checked via FeatureManagement.checkPermission.
 *  testBypassOverride is an @TestVisible static that lets test methods inject
 *  the boolean result without provisioning the perm; null means "no override,
 *  use real check." Tests already rely on this contract — preserved verbatim.
 *
 *  Public surface (do not change without updating callers)
 *  -------------------------------------------------------
 *      buildCompositeKey(Projection__c)  — used by:
 *          ProjectionRollupQueueable, ProjectionService,
 *          ProjectionRollupQueueableTest, ProjectionTriggerHandlerTest
 *      testBypassOverride                 — used by ProjectionTriggerHandlerTest
 *      STAGE_RANK, BYPASS_PERMISSION      — @TestVisible, internal use
 * =============================================================================
 */
public with sharing class ProjectionTriggerHandler extends TriggerHandler {

    // =========================================================================
    //  Constants and overrides
    // =========================================================================

    @TestVisible
    private static final String BYPASS_PERMISSION = 'System_Budget_Lock_Bypass';

    /**
     * Forecast_Stage__c rank used for the illegal-regression check.
     * NA is intentionally absent: any stage may transition to/from NA freely.
     */
    @TestVisible
    private static final Map<String, Integer> STAGE_RANK = new Map<String, Integer>{
        'Stage 0' => 0,
        'Stage 1' => 1,
        'Stage 2' => 2,
        'Stage 3' => 3,
        'Stage 4' => 4,
        'Stage 5' => 5,
        'Booked'  => 6
    };

    /**
     * Test seam: when non-null, blockIllegalRegression uses this value
     * instead of FeatureManagement.checkPermission. Setting this directly
     * is the established pattern in ProjectionTriggerHandlerTest.
     */
    @TestVisible
    private static Boolean testBypassOverride = null;

    // =========================================================================
    //  Phase methods
    // =========================================================================

    protected override void beforeInsert() {
        List<Projection__c> records = (List<Projection__c>) Trigger.new;
        stampCompositeKeys(records);
        // No oldMap on insert — regression check only meaningful on update.
    }

    protected override void beforeUpdate() {
        List<Projection__c> records = (List<Projection__c>) Trigger.new;
        Map<Id, Projection__c> oldMap = (Map<Id, Projection__c>) Trigger.oldMap;
        stampCompositeKeys(records);
        blockIllegalRegression(records, oldMap);
    }

    protected override void afterUpdate() {
        publishStageChangeEvents(
            (List<Projection__c>) Trigger.new,
            (Map<Id, Projection__c>) Trigger.oldMap
        );
    }

    // =========================================================================
    //  Composite key
    // =========================================================================

    @TestVisible
    private static void stampCompositeKeys(List<Projection__c> records) {
        for (Projection__c proj : records) {
            proj.Composite_Key__c = buildCompositeKey(proj);
        }
    }

    /**
     * Build the canonical composite key for a Projection__c row from its
     * five dimension fields. Format: "Account|Category|RevenueType|Year|Month".
     * Null/missing dimensions become empty segments — preserves field count
     * so every key has the same shape, which downstream code relies on when
     * splitting on the pipe.
     *
     * Public static; called from outside this class. DO NOT change the
     * signature without updating ProjectionRollupQueueable, ProjectionService,
     * and the affected tests.
     */
    public static String buildCompositeKey(Projection__c proj) {
        String accountPart  = proj.Account__c       != null ? String.valueOf(proj.Account__c)            : '';
        String categoryPart = proj.Category__c      != null ? String.valueOf(proj.Category__c)           : '';
        String typePart     = proj.Revenue_Type__c  != null ? proj.Revenue_Type__c                       : '';
        String yearPart     = proj.Period_Year__c   != null ? String.valueOf(proj.Period_Year__c.intValue())  : '';
        String monthPart    = proj.Period_Month__c  != null ? String.valueOf(proj.Period_Month__c.intValue()) : '';
        return accountPart + '|' + categoryPart + '|' + typePart + '|' + yearPart + '|' + monthPart;
    }

    // =========================================================================
    //  Forecast stage regression block
    // =========================================================================

    /**
     * Reject updates that move Forecast_Stage__c "down" the rank order
     * (e.g. Stage 4 → Stage 2) unless the running user has the bypass perm
     * or the test seam has been set.
     *
     * NA is exempt — its rank lookup returns null, so the comparison short-circuits.
     */
    @TestVisible
    private static void blockIllegalRegression(
        List<Projection__c> records,
        Map<Id, Projection__c> oldMap
    ) {
        if (oldMap == null) return;

        // Check perm once per transaction. Test seam wins when set.
        Boolean canBypass = (testBypassOverride != null)
            ? testBypassOverride
            : FeatureManagement.checkPermission(BYPASS_PERMISSION);
        if (canBypass) return;

        for (Projection__c proj : records) {
            Projection__c prior = oldMap.get(proj.Id);
            if (prior == null) continue;
            if (proj.Forecast_Stage__c == prior.Forecast_Stage__c) continue;

            Integer newRank = STAGE_RANK.get(proj.Forecast_Stage__c);
            Integer oldRank = STAGE_RANK.get(prior.Forecast_Stage__c);
            // null on either side = NA or unknown picklist value — allow.
            if (newRank == null || oldRank == null) continue;

            if (newRank < oldRank) {
                proj.Forecast_Stage__c.addError(
                    'Illegal forecast stage regression: ' + prior.Forecast_Stage__c + ' → ' +
                    proj.Forecast_Stage__c + '. Requires the System Budget Lock Bypass permission.'
                );
            }
        }
    }

    // =========================================================================
    //  Platform event publish
    // =========================================================================

    /**
     * Publish a Forecast_Stage_Changed__e for every row whose Forecast_Stage__c
     * actually changed. Subscribers (snapshot scheduler, audit logger) handle
     * downstream side-effects async.
     *
     * EventBus.publish is bulk-safe and limit-friendly; we only publish a list
     * once at the end. If the list is empty we skip the call entirely so we
     * don't burn an unnecessary EventBus quota slot.
     */
    @TestVisible
    private static void publishStageChangeEvents(
        List<Projection__c> records,
        Map<Id, Projection__c> oldMap
    ) {
        if (oldMap == null) return;

        List<Forecast_Stage_Changed__e> events = new List<Forecast_Stage_Changed__e>();
        Datetime now = Datetime.now();
        Id userId    = UserInfo.getUserId();

        for (Projection__c proj : records) {
            Projection__c prior = oldMap.get(proj.Id);
            if (prior == null) continue;
            if (proj.Forecast_Stage__c == prior.Forecast_Stage__c) continue;

            events.add(new Forecast_Stage_Changed__e(
                Projection_Id__c = proj.Id,
                Old_Stage__c     = prior.Forecast_Stage__c,
                New_Stage__c     = proj.Forecast_Stage__c,
                Changed_By_Id__c = userId,
                Changed_At__c    = now
            ));
        }

        if (!events.isEmpty()) EventBus.publish(events);
    }
}
