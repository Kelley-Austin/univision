/**
 * AuraEnabled controller backing periodCloseActions LWC and periodCloseDashboard LWC.
 *
 * getPeriodSummary      — returns current status, projections count, projections
 *                         without actuals count, and last-closed datetime for a
 *                         specific Period_Close__c record (used by periodCloseActions).
 *
 * closePeriodAsync      — kicks off close: synchronous for small periods, async
 *                         batch for large ones.
 *
 * reopenPeriod          — delegates to PeriodCloseService.doReopen.
 *
 * getTrailing24Months   — returns trailing 24 months of Period_Close__c with
 *                         aggregated snapshot totals for the dashboard grid.
 *
 * getSnapshotsForPeriod — returns individual snapshot rows for drill-down.
 */
public with sharing class PeriodCloseController {

    // ── Period summary (for periodCloseActions header) ────────────────────────

    public class PeriodSummaryResult {
        @AuraEnabled public String  status;
        @AuraEnabled public Integer projectionCount;
        @AuraEnabled public Integer projectionsWithoutActuals;
        @AuraEnabled public String  closedAt;
        @AuraEnabled public Integer reopenCount;
        @AuraEnabled public Integer periodYear;
        @AuraEnabled public Integer periodMonth;
    }

    @AuraEnabled(cacheable=false)
    public static PeriodSummaryResult getPeriodSummary(Id periodCloseId) {
        Period_Close__c pc = [
            SELECT Status__c, Period_Year__c, Period_Month__c,
                   Closed_At__c, Reopen_Count__c
            FROM   Period_Close__c
            WHERE  Id = :periodCloseId
        ];

        Integer projCount = [
            SELECT COUNT()
            FROM   Projection__c
            WHERE  Period_Year__c  = :pc.Period_Year__c
              AND  Period_Month__c = :pc.Period_Month__c
        ];

        Integer noActuals = (pc.Status__c == 'Open' || pc.Status__c == 'Reopened')
            ? PeriodCloseService.getProjectionsWithoutActuals(periodCloseId)
            : 0;

        PeriodSummaryResult res = new PeriodSummaryResult();
        res.status                  = pc.Status__c;
        res.projectionCount         = projCount;
        res.projectionsWithoutActuals = noActuals;
        res.closedAt                = pc.Closed_At__c != null ? String.valueOf(pc.Closed_At__c) : null;
        res.reopenCount             = pc.Reopen_Count__c != null ? pc.Reopen_Count__c.intValue() : 0;
        res.periodYear              = pc.Period_Year__c  != null ? pc.Period_Year__c.intValue()  : null;
        res.periodMonth             = pc.Period_Month__c != null ? pc.Period_Month__c.intValue() : null;
        return res;
    }

    // ── Close (sync or async) ────────────────────────────────────────────────

    @AuraEnabled
    public static String closePeriodAsync(Id periodCloseId) {
        Period_Close__c pc = [
            SELECT Period_Year__c, Period_Month__c
            FROM   Period_Close__c
            WHERE  Id = :periodCloseId
        ];

        Integer projCount = [
            SELECT COUNT()
            FROM   Projection__c
            WHERE  Period_Year__c  = :pc.Period_Year__c
              AND  Period_Month__c = :pc.Period_Month__c
        ];

        if (projCount <= PeriodCloseBatch.SYNC_THRESHOLD) {
            PeriodCloseService.CloseResult res = PeriodCloseService.doClose(periodCloseId);
            if (!res.success) {
                throw new AuraHandledException(res.errorMessage);
            }
            return 'sync:' + res.snapshotsCreated;
        } else {
            Id jobId = Database.executeBatch(new PeriodCloseBatch(periodCloseId), 200);
            return 'async:' + jobId;
        }
    }

    // ── Reopen ────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static void reopenPeriod(Id periodCloseId) {
        PeriodCloseService.ReopenResult res = PeriodCloseService.doReopen(periodCloseId);
        if (!res.success) {
            throw new AuraHandledException(res.errorMessage);
        }
    }

    // ── Trailing 24 months (for dashboard) ────────────────────────────────────

    public class MonthRow {
        @AuraEnabled public Integer periodYear;
        @AuraEnabled public Integer periodMonth;
        @AuraEnabled public String  status;
        @AuraEnabled public Id      periodCloseId;
        @AuraEnabled public Decimal projectedTotal;
        @AuraEnabled public Decimal actualTotal;
        @AuraEnabled public Decimal variancePct;
        @AuraEnabled public Integer snapshotCount;
    }

    @AuraEnabled(cacheable=true)
    public static List<MonthRow> getTrailing24Months() {
        // Build a list of the last 24 year/month pairs
        List<Integer[]> periods = buildTrailing24();

        // Load all Period_Close__c for those periods
        List<Integer> years  = new List<Integer>();
        List<Integer> months = new List<Integer>();
        for (Integer[] p : periods) {
            years.add(p[0]);
            months.add(p[1]);
        }

        Map<String, Period_Close__c> pcByKey = new Map<String, Period_Close__c>();
        for (Period_Close__c pc : [
            SELECT Id, Status__c, Period_Year__c, Period_Month__c, Closed_At__c
            FROM   Period_Close__c
            WHERE  Period_Year__c IN :years
              AND  Period_Month__c IN :months
        ]) {
            pcByKey.put(pc.Period_Year__c.intValue() + '|' + pc.Period_Month__c.intValue(), pc);
        }

        // Aggregate snapshots grouped by Period_Close__c
        Map<Id, Decimal[]> snapAggByPcId = new Map<Id, Decimal[]>();
        Map<Id, Integer>   snapCountByPcId = new Map<Id, Integer>();
        if (!pcByKey.isEmpty()) {
            Set<Id> pcIds = new Set<Id>();
            for (Period_Close__c pc : pcByKey.values()) pcIds.add(pc.Id);

            for (AggregateResult ar : [
                SELECT Period_Close__c, SUM(Projected_At_Close__c) projSum,
                       SUM(Actual_At_Close__c) actSum, COUNT(Id) cnt
                FROM   Period_Snapshot__c
                WHERE  Period_Close__c IN :pcIds
                GROUP BY Period_Close__c
            ]) {
                Id pcId = (Id) ar.get('Period_Close__c');
                snapAggByPcId.put(pcId, new Decimal[]{
                    (Decimal) ar.get('projSum'),
                    (Decimal) ar.get('actSum')
                });
                snapCountByPcId.put(pcId, ((Decimal) ar.get('cnt')).intValue());
            }
        }

        List<MonthRow> rows = new List<MonthRow>();
        for (Integer[] p : periods) {
            String key = p[0] + '|' + p[1];
            Period_Close__c pc = pcByKey.get(key);

            MonthRow row = new MonthRow();
            row.periodYear  = p[0];
            row.periodMonth = p[1];

            if (pc != null) {
                row.status        = pc.Status__c;
                row.periodCloseId = pc.Id;
                Decimal[] agg = snapAggByPcId.get(pc.Id);
                if (agg != null) {
                    Decimal proj = agg[0] != null ? agg[0] : 0;
                    Decimal act  = agg[1] != null ? agg[1] : 0;
                    row.projectedTotal = proj;
                    row.actualTotal    = act;
                    row.variancePct    = proj != 0
                        ? ((act - proj) / proj * 100).setScale(1)
                        : null;
                    row.snapshotCount  = snapCountByPcId.get(pc.Id);
                }
            } else {
                row.status = 'Not Created';
            }
            rows.add(row);
        }
        return rows;
    }

    // ── Snapshot drill-down ───────────────────────────────────────────────────

    public class SnapshotRow {
        @AuraEnabled public Id      snapshotId;
        @AuraEnabled public String  accountName;
        @AuraEnabled public String  categoryName;
        @AuraEnabled public String  revenueType;
        @AuraEnabled public Decimal projectedAtClose;
        @AuraEnabled public Decimal actualAtClose;
        @AuraEnabled public Decimal varianceAmount;
        @AuraEnabled public Decimal variancePct;
    }

    @AuraEnabled(cacheable=true)
    public static List<SnapshotRow> getSnapshotsForPeriod(Id periodCloseId) {
        List<SnapshotRow> rows = new List<SnapshotRow>();
        for (Period_Snapshot__c snap : [
            SELECT Id,
                   Account__r.Name,
                   Category__r.Name,
                   Revenue_Type__c,
                   Projected_At_Close__c,
                   Actual_At_Close__c,
                   Variance_Amount__c,
                   Variance_Pct__c
            FROM   Period_Snapshot__c
            WHERE  Period_Close__c = :periodCloseId
            ORDER BY Account__r.Name, Category__r.Name
        ]) {
            SnapshotRow row = new SnapshotRow();
            row.snapshotId      = snap.Id;
            row.accountName     = snap.Account__r?.Name;
            row.categoryName    = snap.Category__r?.Name;
            row.revenueType     = snap.Revenue_Type__c;
            row.projectedAtClose = snap.Projected_At_Close__c;
            row.actualAtClose   = snap.Actual_At_Close__c;
            row.varianceAmount  = snap.Variance_Amount__c;
            row.variancePct     = snap.Variance_Pct__c != null
                ? (snap.Variance_Pct__c * 100).setScale(1)
                : null;
            rows.add(row);
        }
        return rows;
    }

    // ── Private: trailing 24 year/month pairs (descending) ───────────────────

    @TestVisible
    static List<Integer[]> buildTrailing24() {
        Date today = Date.today();
        Integer year  = today.year();
        Integer month = today.month();
        List<Integer[]> result = new List<Integer[]>();
        for (Integer i = 0; i < 24; i++) {
            result.add(new Integer[]{ year, month });
            month--;
            if (month == 0) { month = 12; year--; }
        }
        return result;
    }
}
