public with sharing class PeriodCloseController {

    // ── Pre-close warning ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<PeriodCloseService.ProjectionWarning> getProjectionsWithoutActuals(
        Id periodCloseId
    ) {
        return PeriodCloseService.getProjectionsWithoutActuals(periodCloseId);
    }

    // ── State transitions ──────────────────────────────────────────────────────

    @AuraEnabled
    public static PeriodCloseService.CloseResult closePeriod(Id periodCloseId) {
        return PeriodCloseService.closePeriod(periodCloseId);
    }

    @AuraEnabled
    public static PeriodCloseService.CloseResult reopenPeriod(Id periodCloseId) {
        return PeriodCloseService.reopenPeriod(periodCloseId);
    }

    // ── 24-month dashboard summary ─────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<PeriodSummary> getDashboardData() {
        Date today = Date.today();
        Integer currentYear  = today.year();
        Integer currentMonth = today.month();

        // Collect year values for SOQL filter (at most 3 years for 24 months)
        Set<Integer> years = new Set<Integer>();
        Integer yr = currentYear;
        Integer mo = currentMonth;
        for (Integer i = 0; i < 24; i++) {
            years.add(yr);
            mo--;
            if (mo == 0) { mo = 12; yr--; }
        }

        Map<String, Period_Close__c> pcByKey = new Map<String, Period_Close__c>();
        for (Period_Close__c pc : [
            SELECT Id, Status__c, Close_Date__c, Period_Year__c, Period_Month__c
            FROM   Period_Close__c
            WHERE  Period_Year__c IN :years
            ORDER BY Period_Year__c DESC, Period_Month__c DESC
            LIMIT 50
        ]) {
            pcByKey.put(String.valueOf(pc.Period_Year__c.intValue()) + '|' +
                        String.valueOf(pc.Period_Month__c.intValue()), pc);
        }

        Map<String, Decimal> projByKey   = new Map<String, Decimal>();
        Map<String, Decimal> actualByKey = new Map<String, Decimal>();
        for (AggregateResult ar : [
            SELECT Period_Year__c pyr, Period_Month__c pmo,
                   SUM(Projected_At_Close__c) proj,
                   SUM(Actual_At_Close__c)    act
            FROM   Period_Snapshot__c
            WHERE  Period_Year__c IN :years
            GROUP BY Period_Year__c, Period_Month__c
        ]) {
            String key = String.valueOf(((Decimal) ar.get('pyr')).intValue()) + '|' +
                         String.valueOf(((Decimal) ar.get('pmo')).intValue());
            projByKey.put(key,   (Decimal) ar.get('proj'));
            actualByKey.put(key, (Decimal) ar.get('act'));
        }

        List<PeriodSummary> summaries = new List<PeriodSummary>();
        yr = currentYear;
        mo = currentMonth;
        for (Integer i = 0; i < 24; i++) {
            String key = String.valueOf(yr) + '|' + String.valueOf(mo);
            Period_Close__c pc = pcByKey.get(key);

            PeriodSummary s = new PeriodSummary();
            s.periodYear    = yr;
            s.periodMonth   = mo;
            s.periodLabel   = monthLabel(mo) + ' ' + yr;
            s.status        = pc != null ? pc.Status__c : 'No Record';
            s.periodCloseId = pc != null ? pc.Id        : null;

            Decimal projected = projByKey.containsKey(key) ? projByKey.get(key)   : null;
            Decimal actual    = actualByKey.containsKey(key) ? actualByKey.get(key) : null;
            s.projected   = projected;
            s.actual      = actual;
            if (projected != null && projected != 0) {
                s.variancePct = ((actual != null ? actual : 0) - projected) / projected * 100;
            }
            summaries.add(s);

            mo--;
            if (mo == 0) { mo = 12; yr--; }
        }
        return summaries;
    }

    // ── Per-period snapshot drill-down ─────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<SnapshotRow> getPeriodSnapshots(Id periodCloseId) {
        List<SnapshotRow> rows = new List<SnapshotRow>();
        for (Period_Snapshot__c snap : [
            SELECT Id, Account__r.Name, Category__r.Name, Revenue_Type__c,
                   Projected_At_Close__c, Actual_At_Close__c, Variance_Pct__c
            FROM   Period_Snapshot__c
            WHERE  Period_Close__c = :periodCloseId
            ORDER BY Account__r.Name ASC, Category__r.Name ASC
            LIMIT 500
        ]) {
            SnapshotRow row = new SnapshotRow();
            row.snapshotId   = snap.Id;
            row.accountName  = snap.Account__r.Name;
            row.categoryName = snap.Category__r.Name;
            row.revenueType  = snap.Revenue_Type__c;
            row.projected    = snap.Projected_At_Close__c;
            row.actual       = snap.Actual_At_Close__c;
            row.variancePct  = snap.Variance_Pct__c;
            rows.add(row);
        }
        return rows;
    }

    // ── Late-actuals worklist ──────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<LateActualRow> getLateActuals(
        Integer periodYear, Integer periodMonth
    ) {
        String baseQuery =
            'SELECT Id, Account__r.Name, Category__r.Name, Revenue_Type__c, ' +
            '       Amount__c, Period_Year__c, Period_Month__c, Late_Status__c ' +
            'FROM   Actual_Revenue__c ' +
            'WHERE  Is_Late__c = true ' +
            '  AND  Late_Status__c = \'Pending\' ';
        if (periodYear  != null) { baseQuery += 'AND Period_Year__c  = ' + periodYear  + ' '; }
        if (periodMonth != null) { baseQuery += 'AND Period_Month__c = ' + periodMonth + ' '; }
        baseQuery += 'ORDER BY Account__r.Name ASC LIMIT 500';

        List<LateActualRow> rows = new List<LateActualRow>();
        for (Actual_Revenue__c ar : (List<Actual_Revenue__c>) Database.query(baseQuery)) {
            LateActualRow row = new LateActualRow();
            row.actualId    = ar.Id;
            row.accountName = ar.Account__r != null ? ar.Account__r.Name : '';
            row.categoryName = ar.Category__r != null ? ar.Category__r.Name : '';
            row.revenueType = ar.Revenue_Type__c;
            row.amount      = ar.Amount__c;
            row.periodYear  = ar.Period_Year__c  != null ? ar.Period_Year__c.intValue()  : null;
            row.periodMonth = ar.Period_Month__c != null ? ar.Period_Month__c.intValue() : null;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void acceptLateActual(Id actualId) {
        update new Actual_Revenue__c(Id = actualId, Late_Status__c = 'Accepted');
    }

    @AuraEnabled
    public static void rejectLateActual(Id actualId) {
        update new Actual_Revenue__c(Id = actualId, Late_Status__c = 'Rejected');
    }

    // ── Inner DTO types ────────────────────────────────────────────────────────

    public class PeriodSummary {
        @AuraEnabled public Integer periodYear    { get; set; }
        @AuraEnabled public Integer periodMonth   { get; set; }
        @AuraEnabled public String  periodLabel   { get; set; }
        @AuraEnabled public String  status        { get; set; }
        @AuraEnabled public String  periodCloseId { get; set; }
        @AuraEnabled public Decimal projected     { get; set; }
        @AuraEnabled public Decimal actual        { get; set; }
        @AuraEnabled public Decimal variancePct   { get; set; }
    }

    public class SnapshotRow {
        @AuraEnabled public String  snapshotId   { get; set; }
        @AuraEnabled public String  accountName  { get; set; }
        @AuraEnabled public String  categoryName { get; set; }
        @AuraEnabled public String  revenueType  { get; set; }
        @AuraEnabled public Decimal projected    { get; set; }
        @AuraEnabled public Decimal actual       { get; set; }
        @AuraEnabled public Decimal variancePct  { get; set; }
    }

    public class LateActualRow {
        @AuraEnabled public String  actualId     { get; set; }
        @AuraEnabled public String  accountName  { get; set; }
        @AuraEnabled public String  categoryName { get; set; }
        @AuraEnabled public String  revenueType  { get; set; }
        @AuraEnabled public Decimal amount       { get; set; }
        @AuraEnabled public Integer periodYear   { get; set; }
        @AuraEnabled public Integer periodMonth  { get; set; }
    }

    // ── Helper ─────────────────────────────────────────────────────────────────

    private static String monthLabel(Integer m) {
        String[] labels = new String[]{ 'Jan','Feb','Mar','Apr','May','Jun',
                                        'Jul','Aug','Sep','Oct','Nov','Dec' };
        return labels[m - 1];
    }
}
