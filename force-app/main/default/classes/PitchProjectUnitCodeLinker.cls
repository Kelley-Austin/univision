/**
 * Called from ActualRevenueTriggerHandler (before insert and before update when
 * Unit_Code__c changes). Stamps Pitch_Project__c on actuals whose unit code matches
 * an Active pitch project's Pitch_Project_Outlet__c registration.
 *
 * Rules:
 *   - Only stamps when Pitch_Project__c is currently null (never overwrites).
 *   - Only Active pitch projects attract links; Draft/Won/Lost/Cancelled are ignored.
 *   - When multiple Active projects share a unit code, the oldest (CreatedDate ASC) wins.
 */
public with sharing class PitchProjectUnitCodeLinker {

    public static void linkActuals(List<Actual_Revenue__c> actuals) {
        Set<String> codes = new Set<String>();
        for (Actual_Revenue__c a : actuals) {
            if (String.isNotBlank(a.Unit_Code__c) && a.Pitch_Project__c == null) {
                codes.add(a.Unit_Code__c);
            }
        }
        if (codes.isEmpty()) return;

        Map<String, Id> codeToProject = new Map<String, Id>();
        for (Pitch_Project_Outlet__c ppo : [
            SELECT Unit_Code__c, Pitch_Project__c
            FROM   Pitch_Project_Outlet__c
            WHERE  Unit_Code__c IN :codes
              AND  Pitch_Project__r.Status__c = 'Active'
            ORDER BY Pitch_Project__r.CreatedDate ASC
        ]) {
            if (!codeToProject.containsKey(ppo.Unit_Code__c)) {
                codeToProject.put(ppo.Unit_Code__c, ppo.Pitch_Project__c);
            }
        }

        for (Actual_Revenue__c a : actuals) {
            if (String.isNotBlank(a.Unit_Code__c)
                    && a.Pitch_Project__c == null
                    && codeToProject.containsKey(a.Unit_Code__c)) {
                a.Pitch_Project__c = codeToProject.get(a.Unit_Code__c);
            }
        }
    }
}
