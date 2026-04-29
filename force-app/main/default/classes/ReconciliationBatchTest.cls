@isTest
private class ReconciliationBatchTest {

    // ─── Shared test data ─────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Channel__c ch = new Channel__c(
            Name            = 'WUNI',
            Channel_Code__c = 'WUNI',
            Channel_Type__c = 'TV',
            Status__c       = 'Active'
        );
        insert ch;

        Vehicle__c v = new Vehicle__c(
            Name            = 'Noticias',
            Vehicle_Code__c = 'NOTICIAS',
            Status__c       = 'Active'
        );
        insert v;

        Account adv = new Account(Name = 'Test Advertiser');
        insert adv;

        Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
            Account__c    = adv.Id,
            Status__c     = 'Active',
            Market__c     = 'Miami',
            Start_Date__c = Date.newInstance(2026, 1, 1),
            End_Date__c   = Date.newInstance(2026, 12, 31)
        );
        insert opp;

        Advertising_Contract__c contract = new Advertising_Contract__c(
            Advertising_Opportunity__c = opp.Id,
            Contract_Status__c         = 'Active',
            Start_Date__c              = Date.newInstance(2026, 1, 1),
            End_Date__c                = Date.newInstance(2026, 12, 31)
        );
        insert contract;
    }

    // Increments across calls within a test method to ensure unique Counterpoint_Order_ID__c values.
    // Previous test data is rolled back between methods, so a monotonically increasing integer is safe.
    private static Integer actSeq = 0;

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private static Channel__c getChannel() {
        return [SELECT Id FROM Channel__c WHERE Channel_Code__c = 'WUNI' LIMIT 1];
    }

    private static Vehicle__c getVehicle() {
        return [SELECT Id FROM Vehicle__c WHERE Vehicle_Code__c = 'NOTICIAS' LIMIT 1];
    }

    private static Advertising_Opportunity__c getOpp() {
        return [SELECT Id FROM Advertising_Opportunity__c LIMIT 1];
    }

    private static Budget_Line__c makeBudgetLine(Id oppId, Id channelId, Id vehicleId,
                                                  String month, String fiscalYear,
                                                  Decimal plannedAmt, Integer weeklySpots) {
        Budget_Line__c bl = new Budget_Line__c(
            Advertising_Opportunity__c = oppId,
            Channel__c                 = channelId,
            Vehicle__c                 = vehicleId,
            Month__c                   = month,
            Fiscal_Year__c             = fiscalYear,
            Planned_Amount__c          = plannedAmt,
            Weekly_Spots__c            = weeklySpots,
            Status__c                  = 'Approved',
            Date_Type__c               = 'Calendar',
            Calendar_Date__c           = Date.newInstance(2026, 1, 15)
        );
        insert bl;
        return bl;
    }

    private static Actuals_Record__c makeActual(Id channelId, Id vehicleId,
                                                 Date airDate, Decimal netRevenue) {
        actSeq++;
        Actuals_Record__c ar = new Actuals_Record__c(
            Station__c               = channelId,
            Vehicle__c               = vehicleId,
            Calendar_Date__c         = airDate,
            Date_Type__c             = 'Calendar',
            Net_Revenue__c           = netRevenue,
            Gross_Revenue__c         = netRevenue * 1.15,
            Counterpoint_Order_ID__c = 'TST-' + actSeq
        );
        insert ar;
        return ar;
    }

    // ─── Matched scenario ─────────────────────────────────────────────────────

    @isTest
    static void matchedBudgetLine_setsStatusMatchedAndUpdatesActualAmount() {
        Channel__c ch = getChannel();
        Vehicle__c v  = getVehicle();
        Advertising_Opportunity__c opp = getOpp();

        Budget_Line__c bl = makeBudgetLine(opp.Id, ch.Id, v.Id, 'January', '2026', 10000, 5);

        Actuals_Record__c ar = makeActual(ch.Id, v.Id, Date.newInstance(2026, 1, 10), 10000);

        Test.startTest();
        Database.executeBatch(new ReconciliationBatch(opp.Id), 200);
        Test.stopTest();

        Reconciliation_Line__c rec = [
            SELECT Reconciliation_Status__c, Planned_Amount__c, Actual_Amount__c,
                   Variance_Amount__c, Actual_Spot_Count__c, Budget_Line__c
            FROM   Reconciliation_Line__c
            WHERE  Budget_Line__c = :bl.Id
            LIMIT  1
        ];
        System.assertEquals('Matched',    rec.Reconciliation_Status__c, 'Should be Matched');
        System.assertEquals(10000,        rec.Planned_Amount__c,        'Planned should equal budget line');
        System.assertEquals(10000,        rec.Actual_Amount__c,         'Actual should equal actuals net revenue');
        System.assertEquals(0,            rec.Variance_Amount__c,       'No variance expected');
        System.assertEquals(1,            rec.Actual_Spot_Count__c,     'One matching actual');

        Budget_Line__c blRefreshed = [SELECT Actual_Amount__c FROM Budget_Line__c WHERE Id = :bl.Id];
        System.assertEquals(10000, blRefreshed.Actual_Amount__c, 'Budget Line Actual_Amount__c should be updated');
    }

    // ─── Variance scenario ────────────────────────────────────────────────────

    @isTest
    static void varianceBudgetLine_setsStatusVarianceWithCorrectDollarDiff() {
        Channel__c ch = getChannel();
        Vehicle__c v  = getVehicle();
        Advertising_Opportunity__c opp = getOpp();

        Budget_Line__c bl = makeBudgetLine(opp.Id, ch.Id, v.Id, 'February', '2026', 5000, 4);

        // Two actuals in February totaling 4200 (under-delivery by 800)
        makeActual(ch.Id, v.Id, Date.newInstance(2026, 2, 5),  2000);
        makeActual(ch.Id, v.Id, Date.newInstance(2026, 2, 20), 2200);

        Test.startTest();
        Database.executeBatch(new ReconciliationBatch(opp.Id), 200);
        Test.stopTest();

        Reconciliation_Line__c rec = [
            SELECT Reconciliation_Status__c, Actual_Amount__c, Variance_Amount__c, Actual_Spot_Count__c
            FROM   Reconciliation_Line__c
            WHERE  Budget_Line__c = :bl.Id
            LIMIT  1
        ];
        System.assertEquals('Variance', rec.Reconciliation_Status__c, 'Amounts differ so status = Variance');
        System.assertEquals(4200,       rec.Actual_Amount__c,          'Sum of two actuals');
        System.assertEquals(-800,       rec.Variance_Amount__c,        'Under-delivery variance');
        System.assertEquals(2,          rec.Actual_Spot_Count__c,      'Two matching actuals');
    }

    // ─── Unmatched order ──────────────────────────────────────────────────────

    @isTest
    static void unmatchedBudgetLine_setsStatusUnmatchedOrderAndClearsActualAmount() {
        Channel__c ch = getChannel();
        Vehicle__c v  = getVehicle();
        Advertising_Opportunity__c opp = getOpp();

        Budget_Line__c bl = makeBudgetLine(opp.Id, ch.Id, v.Id, 'March', '2026', 8000, 6);
        // No actuals exist for March

        Test.startTest();
        Database.executeBatch(new ReconciliationBatch(opp.Id), 200);
        Test.stopTest();

        Reconciliation_Line__c rec = [
            SELECT Reconciliation_Status__c, Actual_Amount__c, Planned_Amount__c
            FROM   Reconciliation_Line__c
            WHERE  Budget_Line__c = :bl.Id
            LIMIT  1
        ];
        System.assertEquals('Unmatched Order', rec.Reconciliation_Status__c, 'No actuals = Unmatched Order');
        System.assertEquals(0,    rec.Actual_Amount__c,  'No actuals → zero');
        System.assertEquals(8000, rec.Planned_Amount__c, 'Planned amount preserved');

        Budget_Line__c blRefreshed = [SELECT Actual_Amount__c FROM Budget_Line__c WHERE Id = :bl.Id];
        System.assertEquals(null, blRefreshed.Actual_Amount__c, 'Actual_Amount__c cleared when no actuals found');
    }

    // ─── Unmatched actual ─────────────────────────────────────────────────────

    @isTest
    static void unmatchedActual_createdAsUnmatchedActualRowInFinish() {
        Channel__c ch = getChannel();
        Vehicle__c v  = getVehicle();

        // Actual with no corresponding Budget Line
        makeActual(ch.Id, v.Id, Date.newInstance(2026, 4, 8), 3000);

        Test.startTest();
        Database.executeBatch(new ReconciliationBatch(), 200);
        Test.stopTest();

        List<Reconciliation_Line__c> recs = [
            SELECT Reconciliation_Status__c, Actual_Amount__c, Planned_Amount__c, Actual_Spot_Count__c
            FROM   Reconciliation_Line__c
            WHERE  Reconciliation_Status__c = 'Unmatched Actual'
        ];
        System.assertEquals(1,                 recs.size(),                        'One unmatched actual row');
        System.assertEquals('Unmatched Actual', recs[0].Reconciliation_Status__c, 'Status must be Unmatched Actual');
        System.assertEquals(3000,              recs[0].Actual_Amount__c,           'Actual amount from actuals record');
        System.assertEquals(0,                 recs[0].Planned_Amount__c,          'No planned amount');
        System.assertEquals(1,                 recs[0].Actual_Spot_Count__c,       'One spot');
    }

    // ─── Contract linkage ─────────────────────────────────────────────────────

    @isTest
    static void matchedActual_getsLinkedToContractViaOpportunity() {
        Channel__c ch = getChannel();
        Vehicle__c v  = getVehicle();
        Advertising_Opportunity__c opp = getOpp();
        Advertising_Contract__c contract = [SELECT Id FROM Advertising_Contract__c LIMIT 1];

        makeBudgetLine(opp.Id, ch.Id, v.Id, 'May', '2026', 6000, 3);
        Actuals_Record__c ar = makeActual(ch.Id, v.Id, Date.newInstance(2026, 5, 14), 6000);

        Test.startTest();
        Database.executeBatch(new ReconciliationBatch(opp.Id), 200);
        Test.stopTest();

        Actuals_Record__c arRefreshed = [
            SELECT Advertising_Contract__c
            FROM   Actuals_Record__c
            WHERE  Id = :ar.Id
        ];
        System.assertEquals(contract.Id, arRefreshed.Advertising_Contract__c,
            'Matched actual should be linked to its contract');
    }

    // ─── Opportunity-scoped run ───────────────────────────────────────────────

    @isTest
    static void scopedByOpportunity_onlyProcessesBudgetLinesForThatOpp() {
        Channel__c ch = getChannel();
        Vehicle__c v  = getVehicle();
        Advertising_Opportunity__c opp = getOpp();

        // A second opportunity with its own budget line
        Account adv2 = new Account(Name = 'Other Advertiser');
        insert adv2;
        Advertising_Opportunity__c opp2 = new Advertising_Opportunity__c(
            Account__c    = adv2.Id,
            Status__c     = 'Active',
            Market__c     = 'Houston',
            Start_Date__c = Date.newInstance(2026, 1, 1),
            End_Date__c   = Date.newInstance(2026, 12, 31)
        );
        insert opp2;
        makeBudgetLine(opp2.Id, ch.Id, v.Id, 'June', '2026', 4000, 2);

        // Budget line for the target opportunity
        makeBudgetLine(opp.Id, ch.Id, v.Id, 'June', '2026', 9000, 8);

        Test.startTest();
        Database.executeBatch(new ReconciliationBatch(opp.Id), 200);
        Test.stopTest();

        // Only the budget line for opp should have a reconciliation line
        List<Reconciliation_Line__c> recs = [SELECT Advertising_Opportunity__c FROM Reconciliation_Line__c];
        for (Reconciliation_Line__c r : recs) {
            if (r.Advertising_Opportunity__c != null) {
                System.assertEquals(opp.Id, r.Advertising_Opportunity__c,
                    'Scoped run should only create lines for the specified opportunity');
            }
        }
    }

    // ─── Idempotency ─────────────────────────────────────────────────────────

    @isTest
    static void rerun_upsertsByMatchKey_doesNotDuplicate() {
        Channel__c ch = getChannel();
        Vehicle__c v  = getVehicle();
        Advertising_Opportunity__c opp = getOpp();

        makeBudgetLine(opp.Id, ch.Id, v.Id, 'July', '2026', 7000, 4);
        makeActual(ch.Id, v.Id, Date.newInstance(2026, 7, 10), 6500);

        // Run the batch twice in a single test block to verify upsert idempotency
        Test.startTest();
        Database.executeBatch(new ReconciliationBatch(opp.Id), 200);
        Database.executeBatch(new ReconciliationBatch(opp.Id), 200);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Reconciliation_Line__c],
            'Two reconciliation runs should produce one row (upsert, not duplicate)');
    }

    // ─── RunReconciliationAction invocable ────────────────────────────────────

    @isTest
    static void runReconciliationAction_queuesJobAndReturnsSuccess() {
        Advertising_Opportunity__c opp = getOpp();

        RunReconciliationAction.ReconciliationRequest req = new RunReconciliationAction.ReconciliationRequest();
        req.opportunityId = opp.Id;

        Test.startTest();
        List<RunReconciliationAction.ReconciliationResult> results =
            RunReconciliationAction.run(new List<RunReconciliationAction.ReconciliationRequest>{ req });
        Test.stopTest();

        System.assertEquals(1,    results.size(),           'One result per request');
        System.assertEquals(true, results[0].success,       'Should report success');
        System.assert(results[0].message.contains('queued'), 'Message should confirm job queued');
    }

    // ─── buildKey helper ──────────────────────────────────────────────────────

    @isTest
    static void buildKey_nullHandling_doesNotThrow() {
        String key = ReconciliationBatch.buildKey(null, null, null, null);
        System.assert(key != null, 'buildKey should not throw on nulls');
    }
}
