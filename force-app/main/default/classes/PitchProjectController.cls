/**
 * Apex controller for pitchProjectCreator and pitchProjectPacing LWCs.
 *
 * Creator side: getActiveOutlets() + saveProject()
 * Pacing  side: getPacingData()
 */
public with sharing class PitchProjectController {

    // ── Creator ──────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Outlet__c> getActiveOutlets() {
        return [
            SELECT Id, Name, Code__c
            FROM   Outlet__c
            WHERE  Is_Active__c = true
            ORDER BY Name
        ];
    }

    /**
     * Atomically inserts a Pitch_Project__c and its Pitch_Project_Outlet__c children.
     *
     * @param outlets  List of maps, each with keys 'outletId' (Id as String) and 'unitCode' (String).
     * @return         Id of the new Pitch_Project__c record.
     */
    @AuraEnabled
    public static Id saveProject(
        String          projectName,
        String          ownerType,
        String          owningMarketId,
        String          timeFrame,
        Decimal         goal,
        String          description,
        String          startDate,
        String          endDate,
        List<Map<String, String>> outlets
    ) {
        Savepoint sp = Database.setSavepoint();
        try {
            Pitch_Project__c proj = new Pitch_Project__c(
                Project_Name__c  = projectName,
                Owner_Type__c    = ownerType,
                Owning_Market__c = String.isNotBlank(owningMarketId) ? (Id) owningMarketId : null,
                Time_Frame__c    = timeFrame,
                Goal__c          = goal,
                Description__c   = description,
                Start_Date__c    = String.isNotBlank(startDate) ? Date.valueOf(startDate) : null,
                End_Date__c      = String.isNotBlank(endDate)   ? Date.valueOf(endDate)   : null,
                Status__c        = 'Active'
            );
            insert proj;

            List<Pitch_Project_Outlet__c> junctions = new List<Pitch_Project_Outlet__c>();
            for (Map<String, String> outlet : outlets) {
                String outletId = outlet.get('outletId');
                String unitCode = outlet.get('unitCode');
                if (String.isNotBlank(outletId) && String.isNotBlank(unitCode)) {
                    junctions.add(new Pitch_Project_Outlet__c(
                        Pitch_Project__c = proj.Id,
                        Outlet__c        = (Id) outletId,
                        Unit_Code__c     = unitCode.trim()
                    ));
                }
            }
            if (!junctions.isEmpty()) insert junctions;

            return proj.Id;

        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Pacing ───────────────────────────────────────────────────────────────

    /**
     * Returns Goal, Booked, Pending, and Forecast (Weighted) for a Pitch_Project__c.
     *
     * Booked   = SUM(Total_Planned_Amount__c) on linked Opps with StageName = Active | Closed
     * Pending  = SUM on linked Opps with StageName = Submitted | Approved
     * Forecast = probability-weighted sum across all non-Cancelled linked Opps
     *            (Draft=10%, Submitted=30%, Approved=60%, Active/Closed=100%)
     */
    @AuraEnabled(cacheable=true)
    public static PacingData getPacingData(Id projectId) {
        if (projectId == null) throw new AuraHandledException('projectId is required');

        Pitch_Project__c proj = [
            SELECT Goal__c, Status__c, Project_Name__c
            FROM   Pitch_Project__c
            WHERE  Id = :projectId
        ];
        Decimal goalVal = proj.Goal__c != null ? proj.Goal__c : 0;

        AggregateResult[] bookedAgg = [
            SELECT SUM(Total_Planned_Amount__c) total
            FROM   Opportunity
            WHERE  Pitch_Project__c = :projectId
              AND  StageName IN ('Active', 'Closed')
        ];
        Decimal booked = safeDecimal(bookedAgg[0].get('total'));

        AggregateResult[] pendingAgg = [
            SELECT SUM(Total_Planned_Amount__c) total
            FROM   Opportunity
            WHERE  Pitch_Project__c = :projectId
              AND  StageName IN ('Submitted', 'Approved')
        ];
        Decimal pending = safeDecimal(pendingAgg[0].get('total'));

        Map<String, Decimal> weights = new Map<String, Decimal>{
            'Draft'     => 0.10,
            'Submitted' => 0.30,
            'Approved'  => 0.60,
            'Active'    => 1.00,
            'Closed'    => 1.00
        };
        Decimal forecast = 0;
        for (Opportunity opp : [
            SELECT Total_Planned_Amount__c, StageName
            FROM   Opportunity
            WHERE  Pitch_Project__c = :projectId
              AND  StageName        != 'Cancelled'
        ]) {
            Decimal w = weights.containsKey(opp.StageName) ? weights.get(opp.StageName) : 0;
            forecast += safeDecimal(opp.Total_Planned_Amount__c) * w;
        }

        PacingData pd    = new PacingData();
        pd.goal          = goalVal;
        pd.booked        = booked;
        pd.pending       = pending;
        pd.forecast      = forecast;
        pd.projectName   = proj.Project_Name__c;
        pd.projectStatus = proj.Status__c;
        return pd;
    }

    // ── Inner classes ────────────────────────────────────────────────────────

    public class PacingData {
        @AuraEnabled public Decimal goal          { get; set; }
        @AuraEnabled public Decimal booked        { get; set; }
        @AuraEnabled public Decimal pending       { get; set; }
        @AuraEnabled public Decimal forecast      { get; set; }
        @AuraEnabled public String  projectName   { get; set; }
        @AuraEnabled public String  projectStatus { get; set; }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static Decimal safeDecimal(Object val) {
        return val == null ? 0 : (Decimal) val;
    }
}
