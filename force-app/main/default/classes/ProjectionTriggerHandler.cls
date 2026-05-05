public with sharing class ProjectionTriggerHandler {

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

    public static void handleBefore(List<Projection__c> records, Map<Id, Projection__c> oldMap) {
        for (Projection__c proj : records) {
            proj.Composite_Key__c = buildCompositeKey(proj);
        }
        if (oldMap != null) {
            blockIllegalRegression(records, oldMap);
        }
    }

    public static void handleAfterUpdate(List<Projection__c> records, Map<Id, Projection__c> oldMap) {
        if (oldMap == null) return;
        publishStageChangeEvents(records, oldMap);
    }

    public static String buildCompositeKey(Projection__c proj) {
        String accountPart  = proj.Account__c  != null ? String.valueOf(proj.Account__c)   : '';
        String categoryPart = proj.Category__c != null ? String.valueOf(proj.Category__c)  : '';
        String typePart     = proj.Revenue_Type__c != null ? proj.Revenue_Type__c           : '';
        String yearPart     = proj.Period_Year__c  != null ? String.valueOf(proj.Period_Year__c.intValue())  : '';
        String monthPart    = proj.Period_Month__c != null ? String.valueOf(proj.Period_Month__c.intValue()) : '';
        return accountPart + '|' + categoryPart + '|' + typePart + '|' + yearPart + '|' + monthPart;
    }

    // ── Regression block ──────────────────────────────────────────────────────

    @TestVisible
    private static Boolean testBypassOverride = null;

    private static void blockIllegalRegression(List<Projection__c> records, Map<Id, Projection__c> oldMap) {
        Boolean canBypass = testBypassOverride != null
            ? testBypassOverride
            : FeatureManagement.checkPermission(BYPASS_PERMISSION);
        if (canBypass) return;
        for (Projection__c proj : records) {
            Projection__c prior = oldMap.get(proj.Id);
            if (prior == null) continue;
            if (proj.Forecast_Stage__c == prior.Forecast_Stage__c) continue;
            Integer newRank = STAGE_RANK.get(proj.Forecast_Stage__c);
            Integer oldRank = STAGE_RANK.get(prior.Forecast_Stage__c);
            if (newRank == null || oldRank == null) continue; // NA or unknown — skip
            if (newRank < oldRank) {
                proj.Forecast_Stage__c.addError(
                    'Illegal forecast stage regression: ' + prior.Forecast_Stage__c + ' → ' +
                    proj.Forecast_Stage__c + '. Requires the System Budget Lock Bypass permission.'
                );
            }
        }
    }

    // ── Platform event fire ───────────────────────────────────────────────────

    private static void publishStageChangeEvents(List<Projection__c> records, Map<Id, Projection__c> oldMap) {
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
