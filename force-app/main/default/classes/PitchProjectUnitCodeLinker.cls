/**
 * Before-trigger service called by ActualRevenueTriggerHandler.
 *
 * Looks up active Pitch_Project_Outlet__c rows whose Unit_Code__c matches
 * an incoming Actual_Revenue__c.Unit_Code__c value and stamps the Pitch_Project__c
 * lookup on the actual record (before insert/update, so no extra DML needed).
 *
 * Rules:
 * - Only links records where Pitch_Project__c is currently blank (never overwrites).
 * - Only considers Pitch Projects in Active status.
 * - If multiple active projects share the same unit code, the first result wins
 *   (query is ordered by CreatedDate ASC for determinism).
 */
public with sharing class PitchProjectUnitCodeLinker {

    public static void linkActuals(List<Actual_Revenue__c> actuals) {
        if (actuals == null || actuals.isEmpty()) return;

        Set<String> unitCodes = new Set<String>();
        for (Actual_Revenue__c a : actuals) {
            if (String.isNotBlank(a.Unit_Code__c) && a.Pitch_Project__c == null) {
                unitCodes.add(a.Unit_Code__c.trim());
            }
        }
        if (unitCodes.isEmpty()) return;

        // Build unit-code → project map; first Active project wins per code
        Map<String, Id> codeToProject = new Map<String, Id>();
        for (Pitch_Project_Outlet__c ppo : [
            SELECT Unit_Code__c, Pitch_Project__c
            FROM   Pitch_Project_Outlet__c
            WHERE  Unit_Code__c IN :unitCodes
              AND  Pitch_Project__r.Status__c = 'Active'
            ORDER BY CreatedDate ASC
        ]) {
            String code = ppo.Unit_Code__c.trim();
            if (!codeToProject.containsKey(code)) {
                codeToProject.put(code, ppo.Pitch_Project__c);
            }
        }
        if (codeToProject.isEmpty()) return;

        for (Actual_Revenue__c a : actuals) {
            if (a.Pitch_Project__c != null || String.isBlank(a.Unit_Code__c)) continue;
            Id projectId = codeToProject.get(a.Unit_Code__c.trim());
            if (projectId != null) a.Pitch_Project__c = projectId;
        }
    }
}
