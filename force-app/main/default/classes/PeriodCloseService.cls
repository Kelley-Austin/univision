public with sharing class PeriodCloseService {

    // ── Result types ───────────────────────────────────────────────────────────

    public class CloseResult {
        @AuraEnabled public Boolean success       { get; set; }
        @AuraEnabled public String  message       { get; set; }
        @AuraEnabled public Integer snapshotCount { get; set; }
    }

    public class ProjectionWarning {
        @AuraEnabled public String  projectionId    { get; set; }
        @AuraEnabled public String  accountName     { get; set; }
        @AuraEnabled public String  categoryName    { get; set; }
        @AuraEnabled public String  revenueType     { get; set; }
        @AuraEnabled public Decimal projectedAmount { get; set; }
    }

    // ── Projections without any actuals (pre-close warning) ───────────────────

    public static List<ProjectionWarning> getProjectionsWithoutActuals(Id periodCloseId) {
        Period_Close__c pc = [
            SELECT Period_Year__c, Period_Month__c
            FROM   Period_Close__c
            WHERE  Id = :periodCloseId
        ];

        Integer yr = pc.Period_Year__c.intValue();
        Integer mo = pc.Period_Month__c.intValue();

        List<ProjectionWarning> warnings = new List<ProjectionWarning>();
        for (Projection__c proj : [
            SELECT Id, Account__r.Name, Category__r.Name, Revenue_Type__c,
                   Amount__c, Actual_Amount__c
            FROM   Projection__c
            WHERE  Period_Year__c  = :yr
              AND  Period_Month__c = :mo
              AND  Amount__c       > 0
              AND  (Actual_Amount__c = null OR Actual_Amount__c = 0)
        ]) {
            ProjectionWarning w = new ProjectionWarning();
            w.projectionId    = proj.Id;
            w.accountName     = proj.Account__r.Name;
            w.categoryName    = proj.Category__r.Name;
            w.revenueType     = proj.Revenue_Type__c;
            w.projectedAmount = proj.Amount__c;
            warnings.add(w);
        }
        return warnings;
    }

    // ── Close a period ─────────────────────────────────────────────────────────
    // Validates status Open/Reopened, snapshots all Projections, sets Closed.

    public static CloseResult closePeriod(Id periodCloseId) {
        CloseResult result = new CloseResult();

        Period_Close__c pc = [
            SELECT Id, Status__c, Period_Year__c, Period_Month__c, Close_Date__c
            FROM   Period_Close__c
            WHERE  Id = :periodCloseId
            FOR UPDATE
        ];

        if (pc.Status__c != 'Open' && pc.Status__c != 'Reopened') {
            result.success = false;
            result.message = 'Period must be Open or Reopened to close. Current: ' + pc.Status__c;
            return result;
        }

        Integer yr = pc.Period_Year__c.intValue();
        Integer mo = pc.Period_Month__c.intValue();

        List<Projection__c> projections = [
            SELECT Id, Composite_Key__c, Account__c, Category__c, Revenue_Type__c,
                   Amount__c, Actual_Amount__c
            FROM   Projection__c
            WHERE  Period_Year__c  = :yr
              AND  Period_Month__c = :mo
        ];

        List<Period_Snapshot__c> snapshots = new List<Period_Snapshot__c>();
        for (Projection__c proj : projections) {
            Period_Snapshot__c snap = new Period_Snapshot__c(
                Period_Close__c       = periodCloseId,
                Projection__c         = proj.Id,
                Account__c            = proj.Account__c,
                Category__c           = proj.Category__c,
                Revenue_Type__c       = proj.Revenue_Type__c,
                Period_Year__c        = yr,
                Period_Month__c       = mo,
                Projected_At_Close__c = proj.Amount__c       != null ? proj.Amount__c       : 0,
                Actual_At_Close__c    = proj.Actual_Amount__c != null ? proj.Actual_Amount__c : 0
            );
            snap.Composite_Key__c = periodCloseId + '|' + proj.Id;
            snapshots.add(snap);
        }

        if (!snapshots.isEmpty()) {
            upsert snapshots Period_Snapshot__c.Composite_Key__c;
        }

        pc.Status__c     = 'Closed';
        pc.Close_Date__c = Date.today();
        update pc;

        result.success      = true;
        result.snapshotCount = snapshots.size();
        result.message      = 'Period closed. ' + snapshots.size() + ' snapshot(s) created.';
        return result;
    }

    // ── Reopen a period ────────────────────────────────────────────────────────
    // Validates Closed status and blocks reopening a future period.

    public static CloseResult reopenPeriod(Id periodCloseId) {
        CloseResult result = new CloseResult();

        Period_Close__c pc = [
            SELECT Id, Status__c, Period_Year__c, Period_Month__c
            FROM   Period_Close__c
            WHERE  Id = :periodCloseId
            FOR UPDATE
        ];

        if (pc.Status__c != 'Closed') {
            result.success = false;
            result.message = 'Only Closed periods can be reopened. Current: ' + pc.Status__c;
            return result;
        }

        Date today = Date.today();
        Integer pYear  = pc.Period_Year__c.intValue();
        Integer pMonth = pc.Period_Month__c.intValue();
        Boolean isFuture = (pYear > today.year()) ||
                           (pYear == today.year() && pMonth > today.month());
        if (isFuture) {
            result.success = false;
            result.message = 'Cannot reopen a future period.';
            return result;
        }

        pc.Status__c = 'Reopened';
        update pc;

        result.success = true;
        result.message = 'Period reopened successfully.';
        return result;
    }
}
