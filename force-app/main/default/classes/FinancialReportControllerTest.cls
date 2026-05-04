@IsTest
private class FinancialReportControllerTest {

    @TestSetup
    static void makeData() {
        Integer yr       = Date.today().year();
        Date    snapDate = Date.today();

        Account acct1 = new Account(Name = 'FR Account 1');
        Account acct2 = new Account(Name = 'FR Account 2');
        insert new List<Account>{ acct1, acct2 };

        Category__c cat1 = new Category__c(Name = 'Linear');
        Category__c cat2 = new Category__c(Name = 'Streaming');
        insert new List<Category__c>{ cat1, cat2 };

        List<Pacing_Snapshot__c> snaps = new List<Pacing_Snapshot__c>();
        Integer idx = 0;
        for (Account a : new List<Account>{ acct1, acct2 }) {
            for (Category__c c : new List<Category__c>{ cat1, cat2 }) {
                for (Integer mo = 1; mo <= 3; mo++) {
                    idx++;
                    snaps.add(new Pacing_Snapshot__c(
                        Account__c          = a.Id,
                        Category__c         = c.Id,
                        Revenue_Type__c     = 'National',
                        Period_Year__c      = yr,
                        Period_Month__c     = mo,
                        Snapshot_Date__c    = snapDate,
                        Booked_Amount__c    = idx * 1000,
                        Pending_Amount__c   = idx * 500,
                        Forecast_Amount__c  = idx * 1200,
                        Budget_Amount__c    = idx * 1500,
                        Last_Year_Amount__c = idx * 900,
                        Actual_Amount__c    = idx * 950,
                        Composite_Key__c    = a.Id + '|' + c.Id + '|N|' + yr + '|' + mo + '|' + snapDate
                    ));
                }
            }
        }
        insert snaps;
    }

    @IsTest
    static void testGroupByAccount() {
        Integer yr = Date.today().year();
        FinancialReportController.ReportConfig cfg = new FinancialReportController.ReportConfig();
        cfg.periodYear = yr;
        cfg.fromMonth  = 1;
        cfg.toMonth    = 3;
        cfg.groupBy    = 'ACCOUNT';

        List<FinancialReportController.ReportRow> rows =
            FinancialReportController.runReport(JSON.serialize(cfg));

        Assert.isFalse(rows.isEmpty(), 'Should return rows grouped by account');
        // 2 accounts × 2 categories = up to 4 groups with ACCOUNT groupBy per account
        Set<String> keys = new Set<String>();
        for (FinancialReportController.ReportRow r : rows) { keys.add(r.groupKey); }
        Assert.areEqual(2, keys.size(), 'Should have 2 account groups (one per account)');
    }

    @IsTest
    static void testGroupByCategory() {
        Integer yr = Date.today().year();
        FinancialReportController.ReportConfig cfg = new FinancialReportController.ReportConfig();
        cfg.periodYear = yr;
        cfg.fromMonth  = 1;
        cfg.toMonth    = 3;
        cfg.groupBy    = 'CATEGORY';

        List<FinancialReportController.ReportRow> rows =
            FinancialReportController.runReport(JSON.serialize(cfg));

        Set<String> keys = new Set<String>();
        for (FinancialReportController.ReportRow r : rows) { keys.add(r.groupKey); }
        Assert.areEqual(2, keys.size(), 'Should have 2 category groups');
    }

    @IsTest
    static void testGroupByMonth() {
        Integer yr = Date.today().year();
        FinancialReportController.ReportConfig cfg = new FinancialReportController.ReportConfig();
        cfg.periodYear = yr;
        cfg.fromMonth  = 1;
        cfg.toMonth    = 3;
        cfg.groupBy    = 'MONTH';

        List<FinancialReportController.ReportRow> rows =
            FinancialReportController.runReport(JSON.serialize(cfg));

        Set<String> keys = new Set<String>();
        for (FinancialReportController.ReportRow r : rows) { keys.add(r.groupKey); }
        Assert.areEqual(3, keys.size(), 'Should have 3 month groups (Jan-Mar)');
    }

    @IsTest
    static void testGroupByRevenueType() {
        Integer yr = Date.today().year();
        FinancialReportController.ReportConfig cfg = new FinancialReportController.ReportConfig();
        cfg.periodYear  = yr;
        cfg.fromMonth   = 1;
        cfg.toMonth     = 3;
        cfg.groupBy     = 'REVENUE_TYPE';
        cfg.revenueType = 'National';

        List<FinancialReportController.ReportRow> rows =
            FinancialReportController.runReport(JSON.serialize(cfg));

        Assert.isFalse(rows.isEmpty(), 'Revenue type filter should return rows');
        for (FinancialReportController.ReportRow r : rows) {
            Assert.areEqual('National', r.revenueType, 'All rows should be National');
        }
    }

    @IsTest
    static void testDerivedFieldsCalculated() {
        Integer yr = Date.today().year();
        FinancialReportController.ReportConfig cfg = new FinancialReportController.ReportConfig();
        cfg.periodYear = yr;
        cfg.fromMonth  = 1;
        cfg.toMonth    = 3;
        cfg.groupBy    = 'MONTH';

        List<FinancialReportController.ReportRow> rows =
            FinancialReportController.runReport(JSON.serialize(cfg));
        for (FinancialReportController.ReportRow r : rows) {
            Assert.areEqual(r.weightedForecast - r.budget,        r.vsBudgetAmt,   'vsBudgetAmt derived');
            Assert.areEqual(r.weightedForecast - r.lastYearActual, r.vsLastYearAmt, 'vsLyAmt derived');
        }
    }

    @IsTest
    static void testNoSnapshotsReturnsEmpty() {
        FinancialReportController.ReportConfig cfg = new FinancialReportController.ReportConfig();
        cfg.periodYear = 1990;
        cfg.fromMonth  = 1;
        cfg.toMonth    = 12;
        cfg.groupBy    = 'ACCOUNT';

        List<FinancialReportController.ReportRow> rows =
            FinancialReportController.runReport(JSON.serialize(cfg));
        Assert.isTrue(rows.isEmpty(), 'No snapshots for 1990 → empty');
    }

    @IsTest
    static void testInvalidConfigThrows() {
        Boolean threw = false;
        try {
            FinancialReportController.runReport('not-valid-json');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Assert.isTrue(threw, 'Invalid JSON config should throw AuraHandledException');
    }
}
