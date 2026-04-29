@IsTest
private class PeriodCloseControllerTest {

    // ── Helpers ────────────────────────────────────────────────────────────────

    private static Period_Close__c makePC(Integer yr, Integer mo, String status) {
        Period_Close__c pc = new Period_Close__c(
            Period_Year__c  = yr,
            Period_Month__c = mo,
            Status__c       = status,
            Composite_Key__c = String.valueOf(yr) + '|' + String.valueOf(mo)
        );
        insert pc;
        return pc;
    }

    private static Actual_Revenue__c makeLateActual(Account acc) {
        Actual_Revenue__c ar = new Actual_Revenue__c(
            Account__c      = acc.Id,
            Revenue_Type__c = 'Local',
            Period_Year__c  = 2025,
            Period_Month__c = 1,
            Amount__c       = 1000,
            Is_Late__c      = true,
            Late_Status__c  = 'Pending'
        );
        insert ar;
        return ar;
    }

    // ── closePeriod (delegates to service) ────────────────────────────────────

    @IsTest
    static void testClosePeriod_delegatesToService() {
        Period_Close__c pc = makePC(2025, 8, 'Open');

        Test.startTest();
        PeriodCloseService.CloseResult result = PeriodCloseController.closePeriod(pc.Id);
        Test.stopTest();

        System.assert(result.success);
        System.assertEquals(0, result.snapshotCount);
    }

    // ── reopenPeriod (delegates to service) ───────────────────────────────────

    @IsTest
    static void testReopenPeriod_delegatesToService() {
        Period_Close__c pc = makePC(2024, 6, 'Closed');

        Test.startTest();
        PeriodCloseService.CloseResult result = PeriodCloseController.reopenPeriod(pc.Id);
        Test.stopTest();

        System.assert(result.success);
    }

    // ── getDashboardData ───────────────────────────────────────────────────────

    @IsTest
    static void testGetDashboardData_returns24Rows() {
        makePC(2025, 1, 'Closed');
        makePC(2025, 2, 'Open');

        Test.startTest();
        List<PeriodCloseController.PeriodSummary> rows =
            PeriodCloseController.getDashboardData();
        Test.stopTest();

        System.assertEquals(24, rows.size(), 'Should return exactly 24 months');
        // First row should be most recent month
        System.assertEquals(Date.today().year(),  rows[0].periodYear);
        System.assertEquals(Date.today().month(), rows[0].periodMonth);
    }

    @IsTest
    static void testGetDashboardData_statusReflected() {
        Integer yr = Date.today().year();
        Integer mo = Date.today().month() - 1 == 0 ? 12 : Date.today().month() - 1;
        Integer prevYr = mo == 12 ? yr - 1 : yr;
        makePC(prevYr, mo, 'Closed');

        Test.startTest();
        List<PeriodCloseController.PeriodSummary> rows =
            PeriodCloseController.getDashboardData();
        Test.stopTest();

        // Find the row for the closed period
        PeriodCloseController.PeriodSummary closedRow = null;
        for (PeriodCloseController.PeriodSummary r : rows) {
            if (r.periodYear == prevYr && r.periodMonth == mo) {
                closedRow = r;
            }
        }
        System.assertNotEquals(null, closedRow);
        System.assertEquals('Closed', closedRow.status);
    }

    // ── getPeriodSnapshots ─────────────────────────────────────────────────────

    @IsTest
    static void testGetPeriodSnapshots_returnsRows() {
        Period_Close__c pc = makePC(2025, 9, 'Closed');
        Account acc = new Account(Name = 'Snap Account', Type = 'Advertiser');
        insert acc;
        Category__c cat = new Category__c(Name = 'TV');
        insert cat;
        Period_Snapshot__c snap = new Period_Snapshot__c(
            Period_Close__c       = pc.Id,
            Account__c            = acc.Id,
            Category__c           = cat.Id,
            Revenue_Type__c       = 'Local',
            Period_Year__c        = 2025,
            Period_Month__c       = 9,
            Projected_At_Close__c = 5000,
            Actual_At_Close__c    = 4500,
            Composite_Key__c      = pc.Id + '|snap1'
        );
        insert snap;

        Test.startTest();
        List<PeriodCloseController.SnapshotRow> rows =
            PeriodCloseController.getPeriodSnapshots(pc.Id);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(5000, rows[0].projected);
        System.assertEquals(4500, rows[0].actual);
    }

    // ── getLateActuals + accept/reject ────────────────────────────────────────

    @IsTest
    static void testGetLateActuals_filtersByPending() {
        Account acc = new Account(Name = 'Late Acct', Type = 'Advertiser');
        insert acc;
        Actual_Revenue__c ar = makeLateActual(acc);

        Test.startTest();
        List<PeriodCloseController.LateActualRow> rows =
            PeriodCloseController.getLateActuals(2025, 1);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(ar.Id, rows[0].actualId);
    }

    @IsTest
    static void testAcceptLateActual_setsAccepted() {
        Account acc = new Account(Name = 'Accept Acct', Type = 'Advertiser');
        insert acc;
        Actual_Revenue__c ar = makeLateActual(acc);

        Test.startTest();
        PeriodCloseController.acceptLateActual(ar.Id);
        Test.stopTest();

        System.assertEquals('Accepted',
            [SELECT Late_Status__c FROM Actual_Revenue__c WHERE Id = :ar.Id].Late_Status__c);
    }

    @IsTest
    static void testRejectLateActual_setsRejected() {
        Account acc = new Account(Name = 'Reject Acct', Type = 'Advertiser');
        insert acc;
        Actual_Revenue__c ar = makeLateActual(acc);

        Test.startTest();
        PeriodCloseController.rejectLateActual(ar.Id);
        Test.stopTest();

        System.assertEquals('Rejected',
            [SELECT Late_Status__c FROM Actual_Revenue__c WHERE Id = :ar.Id].Late_Status__c);
    }

    @IsTest
    static void testGetLateActuals_noFilter_returnsAll() {
        Account acc = new Account(Name = 'All Late', Type = 'Advertiser');
        insert acc;
        makeLateActual(acc);

        Test.startTest();
        List<PeriodCloseController.LateActualRow> rows =
            PeriodCloseController.getLateActuals(null, null);
        Test.stopTest();

        System.assert(rows.size() >= 1, 'Should return at least one late actual');
    }
}
