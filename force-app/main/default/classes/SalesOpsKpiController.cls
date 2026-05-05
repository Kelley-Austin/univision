public with sharing class SalesOpsKpiController {

    public class KpiData {
        @AuraEnabled public Decimal bookedMtd           { get; set; }
        @AuraEnabled public Decimal weightedForecast    { get; set; }
        @AuraEnabled public Decimal budgetAttainmentPct { get; set; }
        @AuraEnabled public Integer openReconciliations { get; set; }
        @AuraEnabled public Integer lateActualsCount    { get; set; }
        @AuraEnabled public String  periodStatus        { get; set; }
        @AuraEnabled public Integer periodYear          { get; set; }
        @AuraEnabled public Integer periodMonth         { get; set; }
        @AuraEnabled public Date    snapshotDate        { get; set; }
    }

    @AuraEnabled(cacheable=false)
    public static KpiData getKpiData() {
        KpiData d = new KpiData();
        Date    today = Date.today();
        Integer yr    = today.year();
        Integer mo    = today.month();
        d.periodYear  = yr;
        d.periodMonth = mo;
        d.bookedMtd           = 0;
        d.weightedForecast    = 0;
        d.budgetAttainmentPct = 0;

        // Most recent snapshot date for current period
        List<Pacing_Snapshot__c> latest = [
            SELECT Snapshot_Date__c
            FROM   Pacing_Snapshot__c
            WHERE  Period_Year__c  = :yr
              AND  Period_Month__c = :mo
            ORDER BY Snapshot_Date__c DESC
            LIMIT  1
        ];

        if (!latest.isEmpty()) {
            Date snapDate = latest[0].Snapshot_Date__c;
            d.snapshotDate = snapDate;
            for (AggregateResult ar : [
                SELECT SUM(Booked_Amount__c)   booked,
                       SUM(Forecast_Amount__c) forecast,
                       SUM(Budget_Amount__c)   budget
                FROM   Pacing_Snapshot__c
                WHERE  Period_Year__c  = :yr
                  AND  Period_Month__c = :mo
                  AND  Snapshot_Date__c = :snapDate
            ]) {
                Decimal booked   = ar.get('booked')   != null ? (Decimal) ar.get('booked')   : 0;
                Decimal forecast = ar.get('forecast') != null ? (Decimal) ar.get('forecast') : 0;
                Decimal budget   = ar.get('budget')   != null ? (Decimal) ar.get('budget')   : 0;
                d.bookedMtd           = booked;
                d.weightedForecast    = forecast;
                d.budgetAttainmentPct = budget > 0 ? (forecast / budget * 100).setScale(1) : 0;
            }
        }

        // Open (unmatched) staging rows awaiting reconciliation
        d.openReconciliations = [
            SELECT COUNT() FROM Inbound_Staging__c WHERE Status__c = 'Unmatched'
        ];

        // Late actuals pending AE acceptance
        d.lateActualsCount = [
            SELECT COUNT() FROM Actual_Revenue__c
            WHERE Is_Late__c = true AND Late_Status__c = 'Pending'
        ];

        // Period close status for the current month
        List<Period_Close__c> periods = [
            SELECT Status__c
            FROM   Period_Close__c
            WHERE  Period_Year__c  = :yr
              AND  Period_Month__c = :mo
            LIMIT  1
        ];
        d.periodStatus = periods.isEmpty() ? 'No Record' : periods[0].Status__c;

        return d;
    }
}
