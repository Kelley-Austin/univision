@IsTest
private class PeriodCloseServiceTest {

    // ── Test data helpers ─────────────────────────────────────────────────────

    static Period_Close__c insertPc(Integer year, Integer month, String status) {
        Period_Close__c pc = new Period_Close__c(
            Period_Year__c   = year,
            Period_Month__c  = month,
            Close_Date__c    = Date.newInstance(year, month, 1).addDays(14),
            Status__c        = status,
            Composite_Key__c = year + '|' + String.valueOf(month).leftPad(2, '0')
        );
        insert pc;
        return pc;
    }

    static Account insertAccount() {
        Account a = new Account(Name = 'Test Advertiser');
        insert a;
        return a;
    }

    static Projection__c insertProjection(Account a, Integer year, Integer month, Decimal amount, Decimal actual) {
        Projection__c p = new Projection__c(
            Account__c      = a.Id,
            Period_Year__c  = year,
            Period_Month__c = month,
            Amount__c       = amount,
            Actual_Amount__c = actual,
            Stage__c        = 'Working'
        );
        insert p;
        return p;
    }

    // ── closePeriod ───────────────────────────────────────────────────────────

    @IsTest
    static void testCloseOpenPeriod() {
        Account a = insertAccount();
        Period_Close__c pc = insertPc(2025, 10, 'Open');
        insertProjection(a, 2025, 10, 100000, 95000);
        insertProjection(a, 2025, 10, 50000,  0);

        Test.startTest();
        PeriodCloseService.CloseRequest req = new PeriodCloseService.CloseRequest();
        req.periodCloseId = pc.Id;
        List<PeriodCloseService.CloseResult> results =
            PeriodCloseService.closePeriod(new List<PeriodCloseService.CloseRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].success, 'Expected success: ' + results[0].errorMessage);
        System.assertEquals(2, results[0].snapshotsCreated, 'Expected 2 snapshots');

        Period_Close__c updated = [SELECT Status__c, Closed_At__c FROM Period_Close__c WHERE Id = :pc.Id];
        System.assertEquals('Closed', updated.Status__c);
        System.assertNotEquals(null, updated.Closed_At__c);

        List<Period_Snapshot__c> snaps = [
            SELECT Id, Projected_At_Close__c, Actual_At_Close__c
            FROM   Period_Snapshot__c
            WHERE  Period_Close__c = :pc.Id
        ];
        System.assertEquals(2, snaps.size(), 'Expected 2 snapshot rows');
    }

    @IsTest
    static void testCloseAlreadyClosedPeriod() {
        Period_Close__c pc = insertPc(2025, 9, 'Open');
        pc.Status__c = 'Closed';
        update pc;

        Test.startTest();
        PeriodCloseService.CloseResult res = PeriodCloseService.doClose(pc.Id);
        Test.stopTest();

        System.assertEquals(false, res.success);
        System.assert(res.errorMessage.contains('already'), 'Expected already-closed error');
    }

    @IsTest
    static void testClosePeriodNoProjections() {
        Period_Close__c pc = insertPc(2025, 8, 'Open');

        Test.startTest();
        PeriodCloseService.CloseResult res = PeriodCloseService.doClose(pc.Id);
        Test.stopTest();

        System.assert(res.success, 'Close with no projections should still succeed');
        System.assertEquals(0, res.snapshotsCreated);
        System.assertEquals('Closed', [SELECT Status__c FROM Period_Close__c WHERE Id = :pc.Id].Status__c);
    }

    @IsTest
    static void testRecloseAfterReopen() {
        Account a = insertAccount();
        Period_Close__c pc = insertPc(2025, 7, 'Open');
        insertProjection(a, 2025, 7, 75000, 80000);

        // First close
        PeriodCloseService.doClose(pc.Id);

        // Reopen
        pc.Status__c = 'Reopened';
        update pc;

        // Re-close: snapshot upsert should not create duplicate
        Test.startTest();
        PeriodCloseService.CloseResult res = PeriodCloseService.doClose(pc.Id);
        Test.stopTest();

        System.assert(res.success, 'Re-close should succeed');
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Period_Snapshot__c
            WHERE Period_Close__c = :pc.Id
        ], 'Upsert should prevent duplicate snapshot');
    }

    // ── reopenPeriod ──────────────────────────────────────────────────────────

    @IsTest
    static void testReopenClosedPeriod() {
        Period_Close__c pc = insertPc(2025, 6, 'Open');
        pc.Status__c = 'Closed';
        update pc;

        Test.startTest();
        PeriodCloseService.ReopenRequest req = new PeriodCloseService.ReopenRequest();
        req.periodCloseId = pc.Id;
        List<PeriodCloseService.ReopenResult> results =
            PeriodCloseService.reopenPeriod(new List<PeriodCloseService.ReopenRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].success, results[0].errorMessage);

        Period_Close__c updated = [SELECT Status__c, Reopen_Count__c FROM Period_Close__c WHERE Id = :pc.Id];
        System.assertEquals('Reopened', updated.Status__c);
        System.assertEquals(1, updated.Reopen_Count__c.intValue());
    }

    @IsTest
    static void testReopenOpenPeriodBlocked() {
        Period_Close__c pc = insertPc(2025, 5, 'Open');

        Test.startTest();
        PeriodCloseService.ReopenResult res = PeriodCloseService.doReopen(pc.Id);
        Test.stopTest();

        System.assertEquals(false, res.success);
        System.assert(res.errorMessage.contains('Only Closed'), 'Expected status error');
    }

    @IsTest
    static void testReopenFuturePeriodBlocked() {
        Integer futureYear  = Date.today().year() + 1;
        Integer futureMonth = Date.today().month();

        // Insert as Open, force to Closed bypassing the trigger-enforced flow
        // by using a DML-bypass: we can't do that in Apex, so instead insert
        // a Period_Close__c that is already Closed in the DB through manual update.
        Period_Close__c pc = new Period_Close__c(
            Period_Year__c   = futureYear,
            Period_Month__c  = futureMonth,
            Close_Date__c    = Date.newInstance(futureYear, futureMonth, 14),
            Status__c        = 'Open',
            Composite_Key__c = futureYear + '|' + String.valueOf(futureMonth).leftPad(2, '0')
        );
        insert pc;
        // Force closed via direct update (trigger allows Open→Closed for any period)
        pc.Status__c = 'Closed';
        update pc;

        Test.startTest();
        PeriodCloseService.ReopenResult res = PeriodCloseService.doReopen(pc.Id);
        Test.stopTest();

        System.assertEquals(false, res.success);
        System.assert(res.errorMessage.contains('future period'), 'Expected future period error');
    }

    // ── getProjectionsWithoutActuals ─────────────────────────────────────────

    @IsTest
    static void testGetProjectionsWithoutActuals() {
        Account a = insertAccount();
        Period_Close__c pc = insertPc(2025, 4, 'Open');
        insertProjection(a, 2025, 4, 100000, 90000); // has actuals
        insertProjection(a, 2025, 4, 50000,  null);  // no actuals
        insertProjection(a, 2025, 4, 25000,  0);     // zero actuals
        insertProjection(a, 2025, 4, 0,      null);  // Amount = 0, excluded

        Test.startTest();
        Integer count = PeriodCloseService.getProjectionsWithoutActuals(pc.Id);
        Test.stopTest();

        System.assertEquals(2, count, 'Expected 2 projections without actuals');
    }

    // ── generateSnapshots ─────────────────────────────────────────────────────

    @IsTest
    static void testGenerateSnapshots() {
        Account a = insertAccount();
        Period_Close__c pc = insertPc(2025, 3, 'Open');
        insertProjection(a, 2025, 3, 60000, 55000);

        Test.startTest();
        Integer created = PeriodCloseService.generateSnapshots(pc);
        Test.stopTest();

        System.assertEquals(1, created);
        Period_Snapshot__c snap = [
            SELECT Projected_At_Close__c, Actual_At_Close__c
            FROM   Period_Snapshot__c
            WHERE  Period_Close__c = :pc.Id
            LIMIT  1
        ];
        System.assertEquals(60000, snap.Projected_At_Close__c);
        System.assertEquals(55000, snap.Actual_At_Close__c);
    }
}
