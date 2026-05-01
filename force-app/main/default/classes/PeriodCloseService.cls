/**
 * Core service for Period_Close__c state transitions.
 *
 * closePeriod  — Open → Closed. Enqueues PeriodCloseBatch to generate
 *                Period_Snapshot__c rows, then stamps Closed_At__c.
 *
 * reopenPeriod — Closed/Reopened → Reopened. Validates the period is not in
 *                the future. Increments Reopen_Count__c.
 *
 * getProjectionsWithoutActuals — Returns count of Projection__c records for a
 *                                period where Amount__c > 0 but Actual_Amount__c
 *                                is null or zero. Used by LWC to surface the
 *                                "Projections without Actuals" warning before close.
 */
public with sharing class PeriodCloseService {

    // ── Close period ──────────────────────────────────────────────────────────

    public class CloseRequest {
        @InvocableVariable(label='Period Close Id' required=true)
        public Id periodCloseId;
    }

    public class CloseResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
        @InvocableVariable(label='Snapshots Created')
        public Integer snapshotsCreated;
    }

    @InvocableMethod(
        label='Close Period'
        description='Transitions a Period_Close__c from Open to Closed and generates Period_Snapshot__c records.'
        category='Period Management'
    )
    public static List<CloseResult> closePeriod(List<CloseRequest> requests) {
        List<CloseResult> results = new List<CloseResult>();
        for (CloseRequest req : requests) {
            results.add(doClose(req.periodCloseId));
        }
        return results;
    }

    public static CloseResult doClose(Id periodCloseId) {
        CloseResult res = new CloseResult();
        res.success = false;
        res.snapshotsCreated = 0;

        try {
            Period_Close__c pc = [
                SELECT Id, Status__c, Period_Year__c, Period_Month__c
                FROM   Period_Close__c
                WHERE  Id = :periodCloseId
                FOR UPDATE
            ];

            if (pc.Status__c != 'Open' && pc.Status__c != 'Reopened') {
                res.errorMessage = 'Period is already ' + pc.Status__c + ' and cannot be closed again without reopening first.';
                return res;
            }

            // Snapshot generation runs in the same transaction (synchronous batch start)
            Integer created = generateSnapshots(pc);
            res.snapshotsCreated = created;

            pc.Status__c  = 'Closed';
            pc.Closed_At__c = Datetime.now();
            update pc;

            res.success = true;
        } catch (Exception ex) {
            res.errorMessage = ex.getMessage();
        }
        return res;
    }

    // ── Reopen period ─────────────────────────────────────────────────────────

    public class ReopenRequest {
        @InvocableVariable(label='Period Close Id' required=true)
        public Id periodCloseId;
    }

    public class ReopenResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    public static List<ReopenResult> reopenPeriod(List<ReopenRequest> requests) {
        List<ReopenResult> results = new List<ReopenResult>();
        for (ReopenRequest req : requests) {
            results.add(doReopen(req.periodCloseId));
        }
        return results;
    }

    public static ReopenResult doReopen(Id periodCloseId) {
        ReopenResult res = new ReopenResult();
        res.success = false;

        try {
            Period_Close__c pc = [
                SELECT Id, Status__c, Period_Year__c, Period_Month__c, Reopen_Count__c
                FROM   Period_Close__c
                WHERE  Id = :periodCloseId
                FOR UPDATE
            ];

            if (pc.Status__c != 'Closed') {
                res.errorMessage = 'Only Closed periods can be reopened. Current status: ' + pc.Status__c;
                return res;
            }

            // Guard: cannot reopen a future period
            Date today = Date.today();
            Integer year  = pc.Period_Year__c  != null ? pc.Period_Year__c.intValue()  : 0;
            Integer month = pc.Period_Month__c != null ? pc.Period_Month__c.intValue() : 0;
            if (year > today.year() || (year == today.year() && month > today.month())) {
                res.errorMessage = 'Cannot reopen a future period (' + month + '/' + year + ').';
                return res;
            }

            pc.Status__c     = 'Reopened';
            pc.Reopen_Count__c = (pc.Reopen_Count__c != null ? pc.Reopen_Count__c : 0) + 1;
            update pc;

            res.success = true;
        } catch (Exception ex) {
            res.errorMessage = ex.getMessage();
        }
        return res;
    }

    // ── Projections-without-Actuals warning ───────────────────────────────────

    public static Integer getProjectionsWithoutActuals(Id periodCloseId) {
        Period_Close__c pc = [
            SELECT Period_Year__c, Period_Month__c
            FROM   Period_Close__c
            WHERE  Id = :periodCloseId
        ];

        return [
            SELECT COUNT()
            FROM   Projection__c
            WHERE  Period_Year__c   = :pc.Period_Year__c
              AND  Period_Month__c  = :pc.Period_Month__c
              AND  Amount__c        > 0
              AND  (Actual_Amount__c = null OR Actual_Amount__c = 0)
        ];
    }

    // ── Snapshot generation (called synchronously during close) ───────────────

    @TestVisible
    static Integer generateSnapshots(Period_Close__c pc) {
        List<Projection__c> projs = [
            SELECT Id, Account__c, Category__c, Revenue_Type__c,
                   Period_Year__c, Period_Month__c, Amount__c, Actual_Amount__c
            FROM   Projection__c
            WHERE  Period_Year__c  = :pc.Period_Year__c
              AND  Period_Month__c = :pc.Period_Month__c
        ];

        if (projs.isEmpty()) return 0;

        List<Period_Snapshot__c> snapshots = new List<Period_Snapshot__c>();
        for (Projection__c proj : projs) {
            snapshots.add(new Period_Snapshot__c(
                Period_Close__c          = pc.Id,
                Projection__c            = proj.Id,
                Account__c               = proj.Account__c,
                Category__c              = proj.Category__c,
                Revenue_Type__c          = proj.Revenue_Type__c,
                Period_Year__c           = proj.Period_Year__c,
                Period_Month__c          = proj.Period_Month__c,
                Projected_At_Close__c    = proj.Amount__c        != null ? proj.Amount__c        : 0,
                Actual_At_Close__c       = proj.Actual_Amount__c != null ? proj.Actual_Amount__c : 0,
                Snapshot_Composite_Key__c = pc.Id + '|' + proj.Id
            ));
        }

        // Upsert prevents duplicates when a re-close happens after a reopen
        Database.upsert(snapshots, Period_Snapshot__c.Snapshot_Composite_Key__c, false);
        return snapshots.size();
    }
}
