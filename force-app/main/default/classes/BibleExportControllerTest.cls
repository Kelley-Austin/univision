@IsTest
private class BibleExportControllerTest {

    static Account    acct;
    static Category__c cat;

    static void insertSnapshots(Integer yr, Integer fromMo, Integer toMo, Date snapDate) {
        if (acct == null) {
            acct = new Account(Name = 'Bible Test Account');
            insert acct;
            cat = new Category__c(Name = 'Digital');
            insert cat;
        }
        List<Pacing_Snapshot__c> snaps = new List<Pacing_Snapshot__c>();
        for (Integer mo = fromMo; mo <= toMo; mo++) {
            snaps.add(new Pacing_Snapshot__c(
                Account__c          = acct.Id,
                Category__c         = cat.Id,
                Revenue_Type__c     = 'National',
                Period_Year__c      = yr,
                Period_Month__c     = mo,
                Snapshot_Date__c    = snapDate,
                Booked_Amount__c    = 10000,
                Pending_Amount__c   = 5000,
                Forecast_Amount__c  = 13000,
                Budget_Amount__c    = 15000,
                Last_Year_Amount__c = 9000,
                Actual_Amount__c    = 10000,
                Composite_Key__c    = acct.Id + '|' + cat.Id + '|National|' + yr + '|' + mo + '|' + snapDate
            ));
        }
        insert snaps;
    }

    @IsTest
    static void testGetBibleDataFullYear() {
        Integer yr       = Date.today().year();
        Date    snapDate = Date.today();
        acct = new Account(Name = 'Bible Test Account');
        insert acct;
        cat = new Category__c(Name = 'Digital');
        insert cat;
        insertSnapshots(yr, 1, 12, snapDate);

        List<BibleExportController.BibleRow> rows =
            BibleExportController.getBibleData(yr, 1, 12, null, null, null);

        Assert.areEqual(12, rows.size(), 'Should return 12 monthly rows');
        BibleExportController.BibleRow row = rows[0];
        Assert.areEqual(10000, row.booked,           'Booked matches snapshot');
        Assert.areEqual(13000, row.weightedForecast, 'Forecast matches snapshot');
        Assert.isNotNull(row.vsBudgetAmt,            'vs-Budget amount computed');
        Assert.isNotNull(row.vsLastYearAmt,          'vs-LY amount computed');
        Assert.isNotNull(row.vsBudgetPct,            'vs-Budget pct computed');
    }

    @IsTest
    static void testGetBibleDataMonthFilter() {
        Integer yr       = Date.today().year();
        Date    snapDate = Date.today();
        acct = new Account(Name = 'Bible Test Account 2');
        insert acct;
        cat = new Category__c(Name = 'Digital B');
        insert cat;
        insertSnapshots(yr, 1, 12, snapDate);

        List<BibleExportController.BibleRow> rows =
            BibleExportController.getBibleData(yr, 1, 3, null, null, null);
        Assert.areEqual(3, rows.size(), 'Month filter should return Jan-Mar only');
    }

    @IsTest
    static void testGetBibleDataAccountFilter() {
        Integer yr       = Date.today().year();
        Date    snapDate = Date.today();
        acct = new Account(Name = 'Bible Test Account 3');
        insert acct;
        cat = new Category__c(Name = 'Digital C');
        insert cat;
        insertSnapshots(yr, 1, 12, snapDate);

        // Filter to specific account
        List<BibleExportController.BibleRow> rows =
            BibleExportController.getBibleData(yr, 1, 12, acct.Id, null, null);
        Assert.isFalse(rows.isEmpty(), 'Account filter should return rows for that account');
        for (BibleExportController.BibleRow r : rows) {
            Assert.areEqual(acct.Id, r.accountId, 'All rows should belong to filtered account');
        }
    }

    @IsTest
    static void testGetBibleDataNoSnapshots() {
        List<BibleExportController.BibleRow> rows =
            BibleExportController.getBibleData(1990, 1, 12, null, null, null);
        Assert.isTrue(rows.isEmpty(), 'No snapshots for 1990 → empty result');
    }

    @IsTest
    static void testBudgetAndLyPctCalc() {
        Integer yr       = Date.today().year();
        Date    snapDate = Date.today();
        acct = new Account(Name = 'Bible Test Account 4');
        insert acct;
        cat = new Category__c(Name = 'Digital D');
        insert cat;
        insertSnapshots(yr, 1, 1, snapDate);

        List<BibleExportController.BibleRow> rows =
            BibleExportController.getBibleData(yr, 1, 1, null, null, null);
        Assert.areEqual(1, rows.size());
        BibleExportController.BibleRow r = rows[0];
        // vsBudgetPct = (13000/15000 - 1) * 100 ≈ -13.3
        Assert.isTrue(r.vsBudgetPct < 0, 'Forecast below budget → negative pct');
        // vsLyPct = (13000/9000 - 1) * 100 ≈ +44.4
        Assert.isTrue(r.vsLastYearPct > 0, 'Forecast above LY → positive pct');
    }
}
