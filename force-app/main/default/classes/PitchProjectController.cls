/**
 * AuraEnabled controller backing the pitchProjectCreator wizard and pitchProjectPacing
 * record-page component.
 *
 * Pacing stage weights (applied to Budget_Line__c.Planned_Amount__c):
 *   Locked   → 100% (Booked)
 *   Approved → 60%  (Pending)
 *   Draft    → 10%  (Pending)
 *   Cancelled → excluded
 */
public with sharing class PitchProjectController {

    // ── Wizard helpers ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Outlet__c> getActiveOutlets() {
        return [SELECT Id, Name FROM Outlet__c WHERE Is_Active__c = true ORDER BY Name];
    }

    /**
     * Creates a Pitch_Project__c and its Pitch_Project_Outlet__c junctions atomically.
     * outletIds[i] and unitCodes[i] are parallel arrays; each pair produces one junction.
     * Returns the new project Id on success; throws AuraHandledException on failure.
     */
    @AuraEnabled
    public static Id saveProject(
        String  projectName,
        String  ownerType,
        Id      owningMarketId,
        String  timeFrame,
        Decimal goal,
        Date    startDate,
        Date    endDate,
        String  description,
        List<Id>     outletIds,
        List<String> unitCodes
    ) {
        Savepoint sp = Database.setSavepoint();
        try {
            Pitch_Project__c proj = new Pitch_Project__c(
                Project_Name__c  = projectName,
                Owner_Type__c    = ownerType,
                Owning_Market__c = owningMarketId,
                Time_Frame__c    = timeFrame,
                Goal__c          = goal,
                Start_Date__c    = startDate,
                End_Date__c      = endDate,
                Description__c   = description,
                Status__c        = 'Draft'
            );
            insert proj;

            if (outletIds != null && !outletIds.isEmpty()) {
                List<Pitch_Project_Outlet__c> junctions = new List<Pitch_Project_Outlet__c>();
                for (Integer i = 0; i < outletIds.size(); i++) {
                    String code = (unitCodes != null && i < unitCodes.size())
                        ? unitCodes[i] : '';
                    if (String.isBlank(code)) continue;
                    junctions.add(new Pitch_Project_Outlet__c(
                        Pitch_Project__c = proj.Id,
                        Outlet__c        = outletIds[i],
                        Unit_Code__c     = code
                    ));
                }
                if (!junctions.isEmpty()) insert junctions;
            }

            return proj.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Pacing data ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static PacingData getPacingData(Id projectId) {
        if (projectId == null) {
            throw new AuraHandledException('projectId is required');
        }

        Pitch_Project__c proj = [
            SELECT Goal__c
            FROM   Pitch_Project__c
            WHERE  Id = :projectId
        ];

        // Aggregate Budget_Line__c amounts via linked opportunities
        Map<String, Decimal> byStatus = new Map<String, Decimal>();
        for (AggregateResult ar : [
            SELECT Status__c s, SUM(Planned_Amount__c) total
            FROM   Budget_Line__c
            WHERE  Advertising_Opportunity__r.Pitch_Project__c = :projectId
              AND  Status__c != 'Cancelled'
            GROUP BY Status__c
        ]) {
            String s = (String) ar.get('s');
            Decimal t = ar.get('total') != null ? (Decimal) ar.get('total') : 0;
            byStatus.put(s, t);
        }

        Decimal locked   = byStatus.containsKey('Locked')   ? byStatus.get('Locked')   : 0;
        Decimal approved = byStatus.containsKey('Approved') ? byStatus.get('Approved') : 0;
        Decimal draft    = byStatus.containsKey('Draft')    ? byStatus.get('Draft')    : 0;

        PacingData pd    = new PacingData();
        pd.goal     = proj.Goal__c != null ? proj.Goal__c : 0;
        pd.booked   = locked;
        pd.pending  = approved + draft;
        pd.forecast = locked + (approved * 0.60) + (draft * 0.10);
        return pd;
    }

    public class PacingData {
        @AuraEnabled public Decimal goal;
        @AuraEnabled public Decimal booked;
        @AuraEnabled public Decimal pending;
        @AuraEnabled public Decimal forecast;
    }
}
