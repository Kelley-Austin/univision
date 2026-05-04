/**
 * "The Bible" — raw pacing extract blending booked / last-year / weighted forecast / budget.
 * Reads the most recent daily Pacing_Snapshot__c for the requested year/month range.
 */
public with sharing class BibleExportController {

    public class BibleRow {
        @AuraEnabled public String  accountId        { get; set; }
        @AuraEnabled public String  accountName      { get; set; }
        @AuraEnabled public String  categoryName     { get; set; }
        @AuraEnabled public String  revenueType      { get; set; }
        @AuraEnabled public Integer periodYear       { get; set; }
        @AuraEnabled public Integer periodMonth      { get; set; }
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

    @AuraEnabled(cacheable=true)
    public static List<BibleRow> getBibleData(
        Integer periodYear, Integer fromMonth, Integer toMonth,
        Id accountId, Id categoryId, String revenueType
    ) {
        Integer yr = periodYear != null ? periodYear : Date.today().year();
        Integer fm = fromMonth  != null ? fromMonth  : 1;
        Integer tm = toMonth    != null ? toMonth    : 12;
        if (fm > tm) { fm = 1; tm = 12; }

        List<Integer> months = new List<Integer>();
        for (Integer m = fm; m <= tm; m++) { months.add(m); }

        // Resolve latest snapshot date for the requested period
        List<Pacing_Snapshot__c> latestSnap = [
            SELECT Snapshot_Date__c
            FROM   Pacing_Snapshot__c
            WHERE  Period_Year__c  = :yr
              AND  Period_Month__c IN :months
            ORDER BY Snapshot_Date__c DESC
            LIMIT  1
        ];
        if (latestSnap.isEmpty()) { return new List<BibleRow>(); }
        Date snapDate = latestSnap[0].Snapshot_Date__c;

        // Build base query with optional dimension filters
        String q = 'SELECT Account__c, Account__r.Name, Category__c, Category__r.Name, '
                 + '  Revenue_Type__c, Period_Year__c, Period_Month__c, '
                 + '  Booked_Amount__c, Pending_Amount__c, Forecast_Amount__c, '
                 + '  Budget_Amount__c, Last_Year_Amount__c, Actual_Amount__c '
                 + 'FROM Pacing_Snapshot__c '
                 + 'WHERE Snapshot_Date__c = :snapDate '
                 + '  AND Period_Year__c  = :yr '
                 + '  AND Period_Month__c IN :months ';
        if (accountId  != null) {
            q += 'AND Account__c  = \'' + String.escapeSingleQuotes(accountId)  + '\' ';
        }
        if (categoryId != null) {
            q += 'AND Category__c = \'' + String.escapeSingleQuotes(categoryId) + '\' ';
        }
        if (String.isNotBlank(revenueType)) {
            q += 'AND Revenue_Type__c = \'' + String.escapeSingleQuotes(revenueType) + '\' ';
        }
        q += 'ORDER BY Account__r.Name, Category__r.Name, Period_Month__c LIMIT 5000';

        List<BibleRow> rows = new List<BibleRow>();
        for (Pacing_Snapshot__c snap : (List<Pacing_Snapshot__c>) Database.query(q)) {
            BibleRow row = new BibleRow();
            row.accountId        = snap.Account__c;
            row.accountName      = snap.Account__r != null ? snap.Account__r.Name : '';
            row.categoryName     = snap.Category__r != null ? snap.Category__r.Name : '';
            row.revenueType      = snap.Revenue_Type__c;
            row.periodYear       = snap.Period_Year__c  != null ? snap.Period_Year__c.intValue()  : 0;
            row.periodMonth      = snap.Period_Month__c != null ? snap.Period_Month__c.intValue() : 0;
            row.periodLabel      = monthLabel(row.periodMonth) + ' ' + row.periodYear;
            row.booked           = nvl(snap.Booked_Amount__c);
            row.pending          = nvl(snap.Pending_Amount__c);
            row.weightedForecast = nvl(snap.Forecast_Amount__c);
            row.budget           = nvl(snap.Budget_Amount__c);
            row.lastYearActual   = nvl(snap.Last_Year_Amount__c);
            row.currentActual    = nvl(snap.Actual_Amount__c);
            row.vsBudgetAmt      = row.weightedForecast - row.budget;
            row.vsBudgetPct      = row.budget != 0
                ? ((row.weightedForecast / row.budget) - 1) * 100
                : null;
            row.vsLastYearAmt    = row.weightedForecast - row.lastYearActual;
            row.vsLastYearPct    = row.lastYearActual != 0
                ? ((row.weightedForecast / row.lastYearActual) - 1) * 100
                : null;
            rows.add(row);
        }
        return rows;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Decimal nvl(Decimal v) { return v != null ? v : 0; }

    private static String monthLabel(Integer m) {
        String[] labels = new String[]{ 'Jan','Feb','Mar','Apr','May','Jun',
                                        'Jul','Aug','Sep','Oct','Nov','Dec' };
        if (m < 1 || m > 12) { return ''; }
        return labels[m - 1];
    }
}
