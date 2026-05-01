@IsTest
private class PeriodCloseControllerTest {

    static Period_Close__c insertPc(Integer year, Integer month, String status) {
        Period_Close__c pc = new Period_Close__c(
            Period_Year__c   = year,
            Period_Month__c  = month,
            Close_Date__c    = Date.newInstance(year, month, 14),
            Status__c        = status,
            Composite_Key__c = year + '|' + String.valueOf(month).leftPad(2, '0')
        );
        insert pc;
        return pc;
    }

    static Account insertAccount() {
        Account a = new Account(Name = 'Controller Test Acct');
        insert a;
        return a;
    }

    static Projection__c insertProj(Account a, Integer year, Integer month, Decimal amt, Decimal actual) {
        Projection__c p = new Projection__c(
            Account__c       = a.Id,
            Period_Year__c   = year,
            Period_Month__c  = month,
            Amount__c        = amt,
            Actual_Amount__c = actual,
            Stage__c         = 'Working'
        );
        insert p;
        return p;
    }

    // ── getPeriodSummary ──────────────────────────────────────────────────────

    @IsTest
    static void testGetPeriodSummary() {
        Account a = insertAccount();
        Period_Close__c pc = insertPc(2025, 11, 'Open');
        insertProj(a, 2025, 11, 80000, 70000);
        insertProj(a, 2025, 11, 40000, null);

        Test.startTest();
        PeriodCloseController.PeriodSummaryResult res =
            PeriodCloseController.getPeriodSummary(pc.Id);
        Test.stopTest();

        System.assertEquals('Open', res.status);
        System.assertEquals(2, res.projectionCount);
        System.assertEquals(1, res.projectionsWithoutActuals);
        System.assertEquals(2025, res.periodYear);
        System.assertEquals(11,   res.periodMonth);
    }

    @IsTest
    static void testGetPeriodSummaryClosedPeriod() {
        Account a = insertAccount();
        Period_Close__c pc = insertPc(2025, 10, 'Open');
        insertProj(a, 2025, 10, 50000, null);

        pc.Status__c = 'Closed';
        pc.Closed_At__c = Datetime.now();
        update pc;

        Test.startTest();
        PeriodCloseController.PeriodSummaryResult res =
            PeriodCloseController.getPeriodSummary(pc.Id);
        Test.stopTest();

        System.assertEquals('Closed', res.status);
        // projectionsWithoutActuals not computed for closed periods
        System.assertEquals(0, res.projectionsWithoutActuals);
        System.assertNotEquals(null, res.closedAt);
    }

    // ── closePeriodAsync (sync path) ──────────────────────────────────────────

    @IsTest
    static void testClosePeriodAsyncSyncPath() {
        Account a = insertAccount();
        Period_Close__c pc = insertPc(2025, 9, 'Open');
        insertProj(a, 2025, 9, 100000, 95000);

        Test.startTest();
        String result = PeriodCloseController.closePeriodAsync(pc.Id);
        Test.stopTest();

        System.assert(result.startsWith('sync:'), 'Expected sync path: ' + result);
        System.assertEquals('Closed', [SELECT Status__c FROM Period_Close__c WHERE Id = :pc.Id].Status__c);
    }

    @IsTest
    static void testClosePeriodAsyncErrorThrows() {
        Period_Close__c pc = insertPc(2025, 8, 'Open');
        pc.Status__c = 'Closed';
        update pc;

        Boolean threw = false;
        Test.startTest();
        try {
            PeriodCloseController.closePeriodAsync(pc.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected AuraHandledException for invalid close');
    }

    // ── reopenPeriod ──────────────────────────────────────────────────────────

    @IsTest
    static void testReopenPeriod() {
        Period_Close__c pc = insertPc(2025, 7, 'Open');
        pc.Status__c = 'Closed';
        update pc;

        Test.startTest();
        PeriodCloseController.reopenPeriod(pc.Id);
        Test.stopTest();

        System.assertEquals('Reopened', [SELECT Status__c FROM Period_Close__c WHERE Id = :pc.Id].Status__c);
    }

    @IsTest
    static void testReopenPeriodThrowsOnInvalid() {
        Period_Close__c pc = insertPc(2025, 6, 'Open');

        Boolean threw = false;
        Test.startTest();
        try {
            PeriodCloseController.reopenPeriod(pc.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected AuraHandledException for invalid reopen');
    }

    // ── getTrailing24Months ───────────────────────────────────────────────────

    @IsTest
    static void testGetTrailing24MonthsEmpty() {
        Test.startTest();
        List<PeriodCloseController.MonthRow> rows = PeriodCloseController.getTrailing24Months();
        Test.stopTest();

        System.assertEquals(24, rows.size(), 'Expected exactly 24 month rows');
    }

    @IsTest
    static void testGetTrailing24MonthsWithData() {
        Account a = insertAccount();
        Date today = Date.today();
        Integer year  = today.year();
        Integer month = today.month();

        Period_Close__c pc = insertPc(year, month, 'Open');
        insertProj(a, year, month, 100000, 90000);
        pc.Status__c = 'Closed';
        pc.Closed_At__c = Datetime.now();
        update pc;

        // Generate a snapshot manually
        insert new Period_Snapshot__c(
            Period_Close__c       = pc.Id,
            Period_Year__c        = year,
            Period_Month__c       = month,
            Projected_At_Close__c = 100000,
            Actual_At_Close__c    = 90000,
            Snapshot_Composite_Key__c = pc.Id + '|fake001'
        );

        Test.startTest();
        List<PeriodCloseController.MonthRow> rows = PeriodCloseController.getTrailing24Months();
        Test.stopTest();

        PeriodCloseController.MonthRow currentRow = null;
        for (PeriodCloseController.MonthRow r : rows) {
            if (r.periodYear == year && r.periodMonth == month) {
                currentRow = r;
                break;
            }
        }
        System.assertNotEquals(null, currentRow, 'Should find current month row');
        System.assertEquals('Closed', currentRow.status);
        System.assertEquals(100000, currentRow.projectedTotal);
        System.assertEquals(90000,  currentRow.actualTotal);
        System.assertEquals(-10.0,  currentRow.variancePct);
    }

    // ── getSnapshotsForPeriod ─────────────────────────────────────────────────

    @IsTest
    static void testGetSnapshotsForPeriod() {
        Account a = insertAccount();
        Period_Close__c pc = insertPc(2025, 5, 'Open');
        insertProj(a, 2025, 5, 75000, 80000);

        insert new Period_Snapshot__c(
            Period_Close__c       = pc.Id,
            Account__c            = a.Id,
            Revenue_Type__c       = 'TV',
            Period_Year__c        = 2025,
            Period_Month__c       = 5,
            Projected_At_Close__c = 75000,
            Actual_At_Close__c    = 80000,
            Snapshot_Composite_Key__c = pc.Id + '|snap001'
        );

        Test.startTest();
        List<PeriodCloseController.SnapshotRow> rows =
            PeriodCloseController.getSnapshotsForPeriod(pc.Id);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(75000, rows[0].projectedAtClose);
        System.assertEquals(80000, rows[0].actualAtClose);
        System.assertEquals(5000,  rows[0].varianceAmount);
        System.assertEquals('TV',  rows[0].revenueType);
    }

    // ── buildTrailing24 ───────────────────────────────────────────────────────

    @IsTest
    static void testBuildTrailing24Structure() {
        List<Integer[]> periods = PeriodCloseController.buildTrailing24();
        System.assertEquals(24, periods.size());
        Date today = Date.today();
        System.assertEquals(today.year(),  periods[0][0]);
        System.assertEquals(today.month(), periods[0][1]);

        // Verify they are consecutive months descending
        for (Integer i = 1; i < periods.size(); i++) {
            Integer prevYear  = periods[i-1][0];
            Integer prevMonth = periods[i-1][1];
            Integer curYear   = periods[i][0];
            Integer curMonth  = periods[i][1];
            if (prevMonth == 1) {
                System.assertEquals(prevYear - 1, curYear);
                System.assertEquals(12, curMonth);
            } else {
                System.assertEquals(prevYear, curYear);
                System.assertEquals(prevMonth - 1, curMonth);
            }
        }
    }
}
