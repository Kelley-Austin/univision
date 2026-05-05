/**
 * Powers the Financial Report Builder LWC.
 * Reads Pacing_Snapshot__c and aggregates in Apex for flexible grouping.
 */
public with sharing class FinancialReportController {

    // ── DTOs ──────────────────────────────────────────────────────────────────

    public class ReportRow {
        @AuraEnabled public String  groupKey         { get; set; }
        @AuraEnabled public String  groupLabel       { get; set; }
        @AuraEnabled public String  accountName      { get; set; }
        @AuraEnabled public String  categoryName     { get; set; }
        @AuraEnabled public String  revenueType      { get; set; }
        @AuraEnabled public String  periodLabel      { get; set; }
        @AuraEnabled public Decimal booked           { get; set; }
        @AuraEnabled public Decimal pending          { get; set; }
        @AuraEnabled public Decimal weightedForecast { get; set; }
        @AuraEnabled public Decimal budget           { get; set; }
        @AuraEnabled public Decimal lastYearActual   { get; set; }
        @AuraEnabled public Decimal currentActual    { get; set; }
        @AuraEnabled public Decimal vsBudgetAmt      { get; set; }
        @AuraEnabled public Decimal vsBudgetPct      { get; set; }
        @AuraEnabled public Decimal vsLastYearAmt    { get; set; }
        @AuraEnabled public Decimal vsLastYearPct    { get; set; }
    }

    public class ReportConfig {
        @AuraEnabled public Integer periodYear  { get; set; }
        @AuraEnabled public Integer fromMonth   { get; set; }
        @AuraEnabled public Integer toMonth     { get; set; }
        // ACCOUNT | CATEGORY | REVENUE_TYPE | MONTH
        @AuraEnabled public String  groupBy     { get; set; }
        @AuraEnabled public String  accountId   { get; set; }
        @AuraEnabled public String  categoryId  { get; set; }
        @AuraEnabled public String  revenueType { get; set; }
    }

    // ── Main entry point ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ReportRow> runReport(String configJson) {
        ReportConfig cfg;
        try {
            cfg = (ReportConfig) JSON.deserialize(configJson, ReportConfig.class);
        } catch (Exception ex) {
            throw new AuraHandledException('Invalid report config: ' + ex.getMessage());
        }

        Integer yr = cfg.periodYear != null ? cfg.periodYear : Date.today().year();
        Integer fm = cfg.fromMonth  != null ? cfg.fromMonth  : 1;
        Integer tm = cfg.toMonth    != null ? cfg.toMonth    : 12;
        if (fm > tm) { fm = 1; tm = 12; }

        List<Integer> months = new List<Integer>();
        for (Integer m = fm; m <= tm; m++) { months.add(m); }

        // Resolve latest snapshot date for the window
        List<Pacing_Snapshot__c> latestSnap = [
            SELECT Snapshot_Date__c
            FROM   Pacing_Snapshot__c
            WHERE  Period_Year__c  = :yr
              AND  Period_Month__c IN :months
            ORDER BY Snapshot_Date__c DESC
            LIMIT  1
        ];
        if (latestSnap.isEmpty()) { return new List<ReportRow>(); }
        Date snapDate = latestSnap[0].Snapshot_Date__c;

        // Query raw snapshots (aggregate in Apex to support relationship traversal)
        String q = 'SELECT Account__c, Account__r.Name, Category__c, Category__r.Name, '
                 + '  Revenue_Type__c, Period_Year__c, Period_Month__c, '
                 + '  Booked_Amount__c, Pending_Amount__c, Forecast_Amount__c, '
                 + '  Budget_Amount__c, Last_Year_Amount__c, Actual_Amount__c '
                 + 'FROM Pacing_Snapshot__c '
                 + 'WHERE Snapshot_Date__c = :snapDate '
                 + '  AND Period_Year__c  = :yr '
                 + '  AND Period_Month__c IN :months ';
        if (String.isNotBlank(cfg.accountId)) {
            q += 'AND Account__c  = \'' + String.escapeSingleQuotes(cfg.accountId)  + '\' ';
        }
        if (String.isNotBlank(cfg.categoryId)) {
            q += 'AND Category__c = \'' + String.escapeSingleQuotes(cfg.categoryId) + '\' ';
        }
        if (String.isNotBlank(cfg.revenueType)) {
            q += 'AND Revenue_Type__c = \'' + String.escapeSingleQuotes(cfg.revenueType) + '\' ';
        }
        q += 'ORDER BY Account__r.Name, Category__r.Name, Period_Month__c LIMIT 5000';

        String groupBy = String.isNotBlank(cfg.groupBy) ? cfg.groupBy.toUpperCase() : 'ACCOUNT';
        Map<String, ReportRow> rowMap = new Map<String, ReportRow>();

        for (Pacing_Snapshot__c snap : (List<Pacing_Snapshot__c>) Database.query(q)) {
            String gk = buildGroupKey(snap, groupBy);
            if (!rowMap.containsKey(gk)) {
                rowMap.put(gk, buildEmptyRow(snap, groupBy, gk));
            }
            accumulate(rowMap.get(gk), snap);
        }

        // Compute derived fields after accumulation
        List<ReportRow> rows = new List<ReportRow>(rowMap.values());
        for (ReportRow row : rows) {
            row.vsBudgetAmt   = row.weightedForecast - row.budget;
            row.vsBudgetPct   = row.budget != 0
                ? ((row.weightedForecast / row.budget) - 1) * 100
                : null;
            row.vsLastYearAmt = row.weightedForecast - row.lastYearActual;
            row.vsLastYearPct = row.lastYearActual != 0
                ? ((row.weightedForecast / row.lastYearActual) - 1) * 100
                : null;
        }
        return rows;
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static String buildGroupKey(Pacing_Snapshot__c snap, String groupBy) {
        Integer pYr = snap.Period_Year__c  != null ? snap.Period_Year__c.intValue()  : 0;
        Integer pMo = snap.Period_Month__c != null ? snap.Period_Month__c.intValue() : 0;
        if (groupBy == 'ACCOUNT')      { return String.valueOf(snap.Account__c);   }
        if (groupBy == 'CATEGORY')     { return String.valueOf(snap.Category__c);  }
        if (groupBy == 'REVENUE_TYPE') { return snap.Revenue_Type__c != null ? snap.Revenue_Type__c : ''; }
        return pYr + '-' + String.valueOf(pMo).leftPad(2, '0');
    }

    private static ReportRow buildEmptyRow(Pacing_Snapshot__c snap, String groupBy, String gk) {
        ReportRow row = new ReportRow();
        Integer pYr = snap.Period_Year__c  != null ? snap.Period_Year__c.intValue()  : 0;
        Integer pMo = snap.Period_Month__c != null ? snap.Period_Month__c.intValue() : 0;
        row.groupKey         = gk;
        row.accountName      = snap.Account__r  != null ? snap.Account__r.Name  : '';
        row.categoryName     = snap.Category__r != null ? snap.Category__r.Name : '';
        row.revenueType      = snap.Revenue_Type__c;
        row.periodLabel      = monthLabel(pMo) + ' ' + pYr;
        row.booked           = 0;
        row.pending          = 0;
        row.weightedForecast = 0;
        row.budget           = 0;
        row.lastYearActual   = 0;
        row.currentActual    = 0;

        if (groupBy == 'ACCOUNT')      { row.groupLabel = row.accountName;  }
        else if (groupBy == 'CATEGORY')     { row.groupLabel = row.categoryName; }
        else if (groupBy == 'REVENUE_TYPE') { row.groupLabel = row.revenueType != null ? row.revenueType : '(none)'; }
        else                                { row.groupLabel = row.periodLabel;  }
        return row;
    }

    private static void accumulate(ReportRow row, Pacing_Snapshot__c snap) {
        row.booked           += nvl(snap.Booked_Amount__c);
        row.pending          += nvl(snap.Pending_Amount__c);
        row.weightedForecast += nvl(snap.Forecast_Amount__c);
        row.budget           += nvl(snap.Budget_Amount__c);
        row.lastYearActual   += nvl(snap.Last_Year_Amount__c);
        row.currentActual    += nvl(snap.Actual_Amount__c);
    }

    private static Decimal nvl(Decimal v) { return v != null ? v : 0; }

    private static String monthLabel(Integer m) {
        String[] labels = new String[]{ 'Jan','Feb','Mar','Apr','May','Jun',
                                        'Jul','Aug','Sep','Oct','Nov','Dec' };
        if (m < 1 || m > 12) { return ''; }
        return labels[m - 1];
    }
}
