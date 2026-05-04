@IsTest
private class ProjectionServiceTest {

    @TestSetup
    static void makeData() {
        Account acct = new Account(Name = 'Test Advertiser', RecordTypeId = advertiserRtId());
        insert acct;

        Category__c cat = new Category__c(Name = 'Sports', Is_Active__c = true);
        insert cat;

        Budget__c budget = new Budget__c(
            Account__c      = acct.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'National TV',
            Period_Year__c  = 2026,
            Jan_Budget__c   = 10000,
            Feb_Budget__c   = 20000
        );
        insert budget;
    }

    // ── Trigger: composite key ────────────────────────────────────────────────

    @IsTest
    static void testCompositeKeySetByTrigger() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c LIMIT 1];

        Projection__c proj = new Projection__c(
            Account__c      = acct.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'Digital',
            Period_Year__c  = 2026,
            Period_Month__c = 3,
            Amount__c       = 5000
        );

        Test.startTest();
        insert proj;
        Test.stopTest();

        Projection__c saved = [SELECT Composite_Key__c FROM Projection__c WHERE Id = :proj.Id];
        String expectedKey = acct.Id + '|' + cat.Id + '|Digital|2026|3';
        System.assertEquals(expectedKey, saved.Composite_Key__c, 'Composite key should be set by trigger');
    }

    @IsTest
    static void testCompositeKeyUpdatedOnUpdate() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c LIMIT 1];

        Projection__c proj = new Projection__c(
            Account__c      = acct.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'Digital',
            Period_Year__c  = 2026,
            Period_Month__c = 1,
            Amount__c       = 1000
        );
        insert proj;

        proj.Revenue_Type__c = 'Radio';

        Test.startTest();
        update proj;
        Test.stopTest();

        Projection__c saved = [SELECT Composite_Key__c FROM Projection__c WHERE Id = :proj.Id];
        String expectedKey = acct.Id + '|' + cat.Id + '|Radio|2026|1';
        System.assertEquals(expectedKey, saved.Composite_Key__c, 'Composite key should update on field change');
    }

    // ── getProjections ────────────────────────────────────────────────────────

    @IsTest
    static void testGetProjectionsReturns12Rows() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c LIMIT 1];

        List<Projection__c> existing = new List<Projection__c>();
        existing.add(new Projection__c(
            Account__c = acct.Id, Category__c = cat.Id,
            Revenue_Type__c = 'National TV', Period_Year__c = 2026,
            Period_Month__c = 6, Amount__c = 75000, Stage__c = 'Committed'
        ));
        insert existing;

        Test.startTest();
        List<ProjectionService.ProjectionRow> rows =
            ProjectionService.getProjections(acct.Id, cat.Id, 'National TV', 2026);
        Test.stopTest();

        System.assertEquals(12, rows.size(), 'Should return exactly 12 rows');

        ProjectionService.ProjectionRow juneRow = null;
        for (ProjectionService.ProjectionRow r : rows) {
            if (r.month == 6) { juneRow = r; }
        }
        System.assertNotEquals(null, juneRow, 'Row for month 6 must exist');
        System.assertEquals(75000, juneRow.amount, 'June amount should match inserted record');
        System.assertEquals('Committed', juneRow.stage, 'June stage should match');
        System.assertEquals('Jun', juneRow.monthLabel, 'June label should be Jun');
    }

    @IsTest
    static void testGetProjectionsEmptyWhenNoData() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c LIMIT 1];

        Test.startTest();
        List<ProjectionService.ProjectionRow> rows =
            ProjectionService.getProjections(acct.Id, cat.Id, 'Streaming', 2027);
        Test.stopTest();

        System.assertEquals(12, rows.size(), 'Should return 12 stub rows even with no data');
        for (ProjectionService.ProjectionRow r : rows) {
            System.assertEquals(0, r.amount, 'Stub rows should have zero amount');
            System.assertEquals('Working', r.stage, 'Stub rows should default to Working stage');
        }
    }

    // ── upsertProjections ─────────────────────────────────────────────────────

    @IsTest
    static void testUpsertProjectionsInsertsNew() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c LIMIT 1];

        List<ProjectionService.ProjectionInput> inputs = new List<ProjectionService.ProjectionInput>();
        for (Integer m = 1; m <= 12; m++) {
            ProjectionService.ProjectionInput inp = new ProjectionService.ProjectionInput();
            inp.accountId   = acct.Id;
            inp.categoryId  = cat.Id;
            inp.revenueType = 'Local TV';
            inp.periodYear  = 2026;
            inp.periodMonth = m;
            inp.amount      = m * 1000;
            inp.stage       = 'Working';
            inputs.add(inp);
        }

        Test.startTest();
        ProjectionService.UpsertResult result =
            ProjectionService.upsertProjections(JSON.serialize(inputs));
        Test.stopTest();

        System.assert(result.success, 'Upsert should succeed: ' + result.message);
        System.assertEquals(12, result.savedCount, 'All 12 months should be saved');
        System.assertEquals(0,  result.errorCount, 'No errors expected');

        Integer count = [SELECT COUNT() FROM Projection__c WHERE Account__c = :acct.Id
                         AND Revenue_Type__c = 'Local TV' AND Period_Year__c = 2026];
        System.assertEquals(12, count, 'Exactly 12 Projection__c records should exist');
    }

    @IsTest
    static void testUpsertProjectionsUpdatesExisting() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c LIMIT 1];

        Projection__c existing = new Projection__c(
            Account__c = acct.Id, Category__c = cat.Id,
            Revenue_Type__c = 'Digital', Period_Year__c = 2026,
            Period_Month__c = 1, Amount__c = 1000
        );
        insert existing;

        ProjectionService.ProjectionInput inp = new ProjectionService.ProjectionInput();
        inp.accountId   = acct.Id;
        inp.categoryId  = cat.Id;
        inp.revenueType = 'Digital';
        inp.periodYear  = 2026;
        inp.periodMonth = 1;
        inp.amount      = 9999;
        inp.stage       = 'Committed';

        Test.startTest();
        ProjectionService.UpsertResult result =
            ProjectionService.upsertProjections(JSON.serialize(new List<ProjectionService.ProjectionInput>{ inp }));
        Test.stopTest();

        System.assert(result.success, 'Upsert should succeed');
        Projection__c updated = [SELECT Amount__c, Stage__c FROM Projection__c WHERE Id = :existing.Id];
        System.assertEquals(9999, updated.Amount__c, 'Amount should be updated to 9999');
        System.assertEquals('Committed', updated.Stage__c, 'Stage should be updated');
        System.assertEquals(1,
            [SELECT COUNT() FROM Projection__c WHERE Revenue_Type__c = 'Digital' AND Period_Month__c = 1],
            'Should still be exactly one record (updated, not duplicated)');
    }

    @IsTest
    static void testUpsertProjectionsBlockedByLock() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c LIMIT 1];

        Budget_Lock__c lock = new Budget_Lock__c(
            Scope_Level__c  = 'Global',
            Period_Year__c  = 2026,
            Is_Active__c    = true,
            Lock_Message__c = 'Year-end freeze in effect.'
        );
        insert lock;

        ProjectionService.ProjectionInput inp = new ProjectionService.ProjectionInput();
        inp.accountId   = acct.Id;
        inp.categoryId  = cat.Id;
        inp.revenueType = 'National TV';
        inp.periodYear  = 2026;
        inp.periodMonth = 3;
        inp.amount      = 500;

        Test.startTest();
        ProjectionService.UpsertResult result =
            ProjectionService.upsertProjections(JSON.serialize(new List<ProjectionService.ProjectionInput>{ inp }));
        Test.stopTest();

        System.assertEquals(false, result.success, 'Upsert should be blocked by global lock');
        System.assert(result.message.contains('freeze'), 'Lock message should be propagated');
        System.assertEquals(0,
            [SELECT COUNT() FROM Projection__c WHERE Revenue_Type__c = 'National TV' AND Period_Month__c = 3],
            'No records should be saved');
    }

    @IsTest
    static void testUpsertProjectionsBadJson() {
        Test.startTest();
        ProjectionService.UpsertResult result =
            ProjectionService.upsertProjections('NOT_JSON');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Bad JSON should return failure');
    }

    @IsTest
    static void testUpsertProjectionsEmptyList() {
        Test.startTest();
        ProjectionService.UpsertResult result =
            ProjectionService.upsertProjections('[]');
        Test.stopTest();

        System.assertEquals(true, result.success, 'Empty list should succeed with no-op');
    }

    // ── getBudgetGridData ─────────────────────────────────────────────────────

    @IsTest
    static void testGetBudgetGridDataReturnsRow() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c LIMIT 1];

        Projection__c proj = new Projection__c(
            Account__c = acct.Id, Category__c = cat.Id,
            Revenue_Type__c = 'National TV', Period_Year__c = 2026,
            Period_Month__c = 1, Amount__c = 5000
        );
        insert proj;

        Actual_Revenue__c actual = new Actual_Revenue__c(
            Account__c = acct.Id, Category__c = cat.Id,
            Revenue_Type__c = 'National TV', Period_Year__c = 2026,
            Period_Month__c = 1, Amount__c = 12000
        );
        insert actual;

        Test.startTest();
        List<ProjectionService.GridRow> rows =
            ProjectionService.getBudgetGridData(acct.Id, cat.Id, 'National TV', 2026);
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'One grid row expected for the budget');
        ProjectionService.GridRow row = rows[0];
        System.assertEquals(30000, row.totalBudget, 'Total budget = Jan(10000) + Feb(20000)');
        System.assertEquals(5000,  row.totalProjection, 'Total projection = 5000');
        System.assertEquals(12000, row.totalActual, 'Total actual = 12000');
        System.assertEquals(12000 - 30000, row.totalVariance, 'Variance = actual - budget');
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Id advertiserRtId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Advertiser')?.getRecordTypeId();
    }
}
