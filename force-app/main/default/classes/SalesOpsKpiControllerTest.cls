@IsTest
private class SalesOpsKpiControllerTest {

    @TestSetup
    static void makeData() {
        Integer yr = Date.today().year();
        Integer mo = Date.today().month();

        Account acct = new Account(Name = 'KPI Test Account');
        insert acct;
        Category__c cat = new Category__c(Name = 'Broadcast');
        insert cat;

        // Pacing snapshot for today
        Pacing_Snapshot__c snap = new Pacing_Snapshot__c(
            Account__c          = acct.Id,
            Category__c         = cat.Id,
            Revenue_Type__c     = 'National',
            Period_Year__c      = yr,
            Period_Month__c     = mo,
            Snapshot_Date__c    = Date.today(),
            Booked_Amount__c    = 50000,
            Pending_Amount__c   = 20000,
            Forecast_Amount__c  = 62000,
            Budget_Amount__c    = 80000,
            Last_Year_Amount__c = 55000,
            Actual_Amount__c    = 45000,
            Composite_Key__c    = acct.Id + '|' + cat.Id + '|National|' + yr + '|' + mo + '|' + Date.today()
        );
        insert snap;

        // Unmatched staging row
        Inbound_Staging__c stg = new Inbound_Staging__c(
            Status__c              = 'Unmatched',
            Raw_Advertiser_Name__c = 'Unknown Co',
            Revenue_Amount__c      = 1000,
            Period_Year__c         = yr,
            Period_Month__c        = mo
        );
        insert stg;

        // Late actual pending review
        Actual_Revenue__c late = new Actual_Revenue__c(
            Account__c      = acct.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'National',
            Period_Year__c  = yr,
            Period_Month__c = mo,
            Amount__c       = 500,
            Is_Late__c      = true,
            Late_Status__c  = 'Pending',
            External_Key__c = acct.Id + '|late|' + yr + '|' + mo
        );
        insert late;

        // Period close record for current month
        Period_Close__c pc = new Period_Close__c(
            Period_Year__c  = yr,
            Period_Month__c = mo,
            Status__c       = 'Open'
        );
        insert pc;
    }

    @IsTest
    static void testGetKpiData() {
        SalesOpsKpiController.KpiData d = SalesOpsKpiController.getKpiData();
        Assert.isNotNull(d, 'KpiData must not be null');
        Assert.areEqual(Date.today().year(),  d.periodYear,  'Year matches today');
        Assert.areEqual(Date.today().month(), d.periodMonth, 'Month matches today');
        Assert.areEqual(50000, d.bookedMtd,        'Booked MTD from snapshot');
        Assert.areEqual(62000, d.weightedForecast, 'Weighted forecast from snapshot');
        Assert.isTrue(d.budgetAttainmentPct > 0,   'Budget attainment computed');
        Assert.areEqual(1, d.openReconciliations,  'One unmatched staging row');
        Assert.areEqual(1, d.lateActualsCount,     'One late actual pending');
        Assert.areEqual('Open', d.periodStatus,    'Period status = Open');
    }

    @IsTest
    static void testNoSnapshotYieldsZeros() {
        delete [SELECT Id FROM Pacing_Snapshot__c];
        SalesOpsKpiController.KpiData d = SalesOpsKpiController.getKpiData();
        Assert.areEqual(0, d.bookedMtd,        'No snapshot → booked = 0');
        Assert.areEqual(0, d.weightedForecast, 'No snapshot → forecast = 0');
    }

    @IsTest
    static void testNoPeriodCloseRecord() {
        delete [SELECT Id FROM Period_Close__c];
        SalesOpsKpiController.KpiData d = SalesOpsKpiController.getKpiData();
        Assert.areEqual('No Record', d.periodStatus, 'No period close → No Record');
    }
}
