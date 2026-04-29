@IsTest
private class PeriodCloseServiceTest {

    // ── Test data helpers ──────────────────────────────────────────────────────

    private static Period_Close__c makePeriodClose(Integer yr, Integer mo, String status) {
        Period_Close__c pc = new Period_Close__c(
            Period_Year__c  = yr,
            Period_Month__c = mo,
            Status__c       = status,
            Composite_Key__c = String.valueOf(yr) + '|' + String.valueOf(mo)
        );
        insert pc;
        return pc;
    }

    private static Account makeAccount() {
        Account acc = new Account(Name = 'Test Advertiser', Type = 'Advertiser');
        insert acc;
        return acc;
    }

    private static Category__c makeCategory() {
        Category__c cat = new Category__c(Name = 'Digital');
        insert cat;
        return cat;
    }

    private static Projection__c makeProjection(
        Account acc, Category__c cat, Integer yr, Integer mo,
        Decimal amount, Decimal actualAmount
    ) {
        Projection__c proj = new Projection__c(
            Account__c      = acc.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'Local',
            Period_Year__c  = yr,
            Period_Month__c = mo,
            Amount__c       = amount,
            Actual_Amount__c = actualAmount,
            Stage__c        = 'Working',
            Composite_Key__c = acc.Id + '|' + cat.Id + '|Local|' + yr + '|' + mo
        );
        insert proj;
        return proj;
    }

    // ── closePeriod: happy path ────────────────────────────────────────────────

    @IsTest
    static void testClosePeriod_createsSnapshots() {
        Account acc = makeAccount();
        Category__c cat = makeCategory();
        Period_Close__c pc = makePeriodClose(2025, 3, 'Open');
        Projection__c proj = makeProjection(acc, cat, 2025, 3, 10000, 9000);

        Test.startTest();
        PeriodCloseService.CloseResult result = PeriodCloseService.closePeriod(pc.Id);
        Test.stopTest();

        System.assert(result.success, 'Expected success');
        System.assertEquals(1, result.snapshotCount);

        Period_Close__c updated = [SELECT Status__c, Close_Date__c FROM Period_Close__c WHERE Id = :pc.Id];
        System.assertEquals('Closed', updated.Status__c);
        System.assertEquals(Date.today(), updated.Close_Date__c);

        List<Period_Snapshot__c> snaps = [
            SELECT Projected_At_Close__c, Actual_At_Close__c, Period_Close__c, Projection__c
            FROM   Period_Snapshot__c
            WHERE  Period_Close__c = :pc.Id
        ];
        System.assertEquals(1, snaps.size());
        System.assertEquals(10000, snaps[0].Projected_At_Close__c);
        System.assertEquals(9000, snaps[0].Actual_At_Close__c);
        System.assertEquals(proj.Id, snaps[0].Projection__c);
    }

    @IsTest
    static void testClosePeriod_reopenedStatusAllowed() {
        Account acc = makeAccount();
        Category__c cat = makeCategory();
        Period_Close__c pc = makePeriodClose(2025, 2, 'Reopened');
        makeProjection(acc, cat, 2025, 2, 5000, 4800);

        Test.startTest();
        PeriodCloseService.CloseResult result = PeriodCloseService.closePeriod(pc.Id);
        Test.stopTest();

        System.assert(result.success);
        Period_Close__c updated = [SELECT Status__c FROM Period_Close__c WHERE Id = :pc.Id];
        System.assertEquals('Closed', updated.Status__c);
    }

    @IsTest
    static void testClosePeriod_upsertOnReclose() {
        Account acc = makeAccount();
        Category__c cat = makeCategory();
        Period_Close__c pc = makePeriodClose(2025, 1, 'Open');
        Projection__c proj = makeProjection(acc, cat, 2025, 1, 8000, 7500);

        // First close
        PeriodCloseService.closePeriod(pc.Id);

        // Reopen and update projection actual
        pc.Status__c = 'Reopened';
        update pc;
        proj.Actual_Amount__c = 8100;
        update proj;

        Test.startTest();
        PeriodCloseService.CloseResult result = PeriodCloseService.closePeriod(pc.Id);
        Test.stopTest();

        System.assert(result.success);
        List<Period_Snapshot__c> snaps = [
            SELECT Actual_At_Close__c FROM Period_Snapshot__c WHERE Period_Close__c = :pc.Id
        ];
        // Should still be 1 record (upserted, not duplicated)
        System.assertEquals(1, snaps.size());
        System.assertEquals(8100, snaps[0].Actual_At_Close__c);
    }

    @IsTest
    static void testClosePeriod_alreadyClosed_fails() {
        Period_Close__c pc = makePeriodClose(2025, 4, 'Closed');

        Test.startTest();
        PeriodCloseService.CloseResult result = PeriodCloseService.closePeriod(pc.Id);
        Test.stopTest();

        System.assert(!result.success);
        System.assert(result.message.contains('Closed'));
    }

    @IsTest
    static void testClosePeriod_noProjections_succeeds() {
        Period_Close__c pc = makePeriodClose(2025, 5, 'Open');

        Test.startTest();
        PeriodCloseService.CloseResult result = PeriodCloseService.closePeriod(pc.Id);
        Test.stopTest();

        System.assert(result.success);
        System.assertEquals(0, result.snapshotCount);
    }

    // ── reopenPeriod ──────────────────────────────────────────────────────────

    @IsTest
    static void testReopenPeriod_pastPeriod_succeeds() {
        Period_Close__c pc = makePeriodClose(2024, 1, 'Closed');

        Test.startTest();
        PeriodCloseService.CloseResult result = PeriodCloseService.reopenPeriod(pc.Id);
        Test.stopTest();

        System.assert(result.success);
        Period_Close__c updated = [SELECT Status__c FROM Period_Close__c WHERE Id = :pc.Id];
        System.assertEquals('Reopened', updated.Status__c);
    }

    @IsTest
    static void testReopenPeriod_notClosed_fails() {
        Period_Close__c pc = makePeriodClose(2024, 2, 'Open');

        Test.startTest();
        PeriodCloseService.CloseResult result = PeriodCloseService.reopenPeriod(pc.Id);
        Test.stopTest();

        System.assert(!result.success);
        System.assert(result.message.contains('Closed'));
    }

    @IsTest
    static void testReopenPeriod_futurePeriod_blocked() {
        Integer futureYear  = Date.today().year() + 1;
        Integer futureMonth = Date.today().month();
        Period_Close__c pc = makePeriodClose(futureYear, futureMonth, 'Closed');

        Test.startTest();
        PeriodCloseService.CloseResult result = PeriodCloseService.reopenPeriod(pc.Id);
        Test.stopTest();

        System.assert(!result.success);
        System.assert(result.message.contains('future'));
    }

    // ── getProjectionsWithoutActuals ───────────────────────────────────────────

    @IsTest
    static void testGetProjectionsWithoutActuals_returnsUnmatched() {
        Account acc = makeAccount();
        Category__c cat = makeCategory();
        Period_Close__c pc = makePeriodClose(2025, 6, 'Open');
        makeProjection(acc, cat, 2025, 6, 5000, null);
        // proj with actuals — should NOT be in warnings
        makeProjection(acc, cat, 2025, 6, 3000, 3000);

        Test.startTest();
        List<PeriodCloseService.ProjectionWarning> warnings =
            PeriodCloseService.getProjectionsWithoutActuals(pc.Id);
        Test.stopTest();

        System.assertEquals(1, warnings.size());
        System.assertEquals(5000, warnings[0].projectedAmount);
    }

    @IsTest
    static void testGetProjectionsWithoutActuals_zeroAmountExcluded() {
        Account acc = makeAccount();
        Category__c cat = makeCategory();
        Period_Close__c pc = makePeriodClose(2025, 7, 'Open');
        // Amount = 0 should not show as a warning
        makeProjection(acc, cat, 2025, 7, 0, null);

        Test.startTest();
        List<PeriodCloseService.ProjectionWarning> warnings =
            PeriodCloseService.getProjectionsWithoutActuals(pc.Id);
        Test.stopTest();

        System.assertEquals(0, warnings.size());
    }
}
