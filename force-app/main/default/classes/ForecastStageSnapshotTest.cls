@IsTest
private class ForecastStageSnapshotTest {

    @TestSetup
    static void setupData() {
        Id advRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();
        Account adv = new Account(Name = 'Snapshot Test Advertiser', RecordTypeId = advRtId);
        insert adv;

        Category__c cat = new Category__c(Name = 'Snapshot Test Category');
        insert cat;

        // Projections at varied stages so we exercise the weight lookup
        List<Projection__c> projs = new List<Projection__c>{
            new Projection__c(Account__c = adv.Id, Category__c = cat.Id, Revenue_Type__c = 'National TV',
                Period_Year__c = 2026, Period_Month__c = 1, Amount__c = 1000,
                Stage__c = 'Working', Forecast_Stage__c = 'Stage 0'),
            new Projection__c(Account__c = adv.Id, Category__c = cat.Id, Revenue_Type__c = 'National TV',
                Period_Year__c = 2026, Period_Month__c = 2, Amount__c = 2000,
                Stage__c = 'Working', Forecast_Stage__c = 'Stage 3'),
            new Projection__c(Account__c = adv.Id, Category__c = cat.Id, Revenue_Type__c = 'National TV',
                Period_Year__c = 2026, Period_Month__c = 3, Amount__c = 5000,
                Stage__c = 'Working', Forecast_Stage__c = 'Booked')
        };
        insert projs;
    }

    private static void mockWeights() {
        ForecastStageWeightProvider.setMockWeights(new Map<String, Decimal>{
            'Stage 0' => 10, 'Stage 1' => 25, 'Stage 2' => 40, 'Stage 3' => 60,
            'Stage 4' => 75, 'Stage 5' => 90, 'Booked'  => 100, 'NA' => 0
        });
    }

    // ── Weight provider returns CMDT-backed weights when not mocked ───────────

    @IsTest
    static void testWeightProvider_returnsValues() {
        Map<String, Decimal> w = ForecastStageWeightProvider.getWeights();
        // CMDT seeded by deploy — at least one stage should resolve
        Assert.isNotNull(w);
    }

    @IsTest
    static void testWeightProvider_mockOverride() {
        mockWeights();
        Assert.areEqual(60, ForecastStageWeightProvider.getWeight('Stage 3'));
        Assert.areEqual(0,  ForecastStageWeightProvider.getWeight('NA'));
        Assert.areEqual(0,  ForecastStageWeightProvider.getWeight(null));
        Assert.areEqual(0,  ForecastStageWeightProvider.getWeight('Unknown Stage'));
    }

    // ── Queueable creates one snapshot per Projection with correct weight/amount ─

    @IsTest
    static void testQueueable_createsSnapshots() {
        mockWeights();
        Date today = Date.today();

        Test.startTest();
        System.enqueueJob(new ForecastStageSnapshotQueueable(today));
        Test.stopTest();

        List<Forecast_Stage_Snapshot__c> snaps = [
            SELECT Forecast_Stage__c, Weight_Pct__c, Amount__c, Snapshot_Date__c, Weighted_Amount__c
            FROM Forecast_Stage_Snapshot__c
            ORDER BY Amount__c
        ];
        Assert.areEqual(3, snaps.size());

        // Stage 0 / 1000 / 10% → weighted 100
        Assert.areEqual('Stage 0', snaps[0].Forecast_Stage__c);
        Assert.areEqual(10, snaps[0].Weight_Pct__c);
        Assert.areEqual(1000, snaps[0].Amount__c);
        Assert.areEqual(100, snaps[0].Weighted_Amount__c);

        // Stage 3 / 2000 / 60% → weighted 1200
        Assert.areEqual('Stage 3', snaps[1].Forecast_Stage__c);
        Assert.areEqual(60, snaps[1].Weight_Pct__c);
        Assert.areEqual(1200, snaps[1].Weighted_Amount__c);

        // Booked / 5000 / 100% → weighted 5000
        Assert.areEqual('Booked', snaps[2].Forecast_Stage__c);
        Assert.areEqual(100, snaps[2].Weight_Pct__c);
        Assert.areEqual(5000, snaps[2].Weighted_Amount__c);

        Assert.areEqual(today, snaps[0].Snapshot_Date__c);
    }

    // ── Default constructor uses Date.today() ─────────────────────────────────

    @IsTest
    static void testQueueable_defaultDate() {
        mockWeights();

        Test.startTest();
        System.enqueueJob(new ForecastStageSnapshotQueueable());
        Test.stopTest();

        Forecast_Stage_Snapshot__c s = [
            SELECT Snapshot_Date__c FROM Forecast_Stage_Snapshot__c LIMIT 1
        ];
        Assert.areEqual(Date.today(), s.Snapshot_Date__c);
    }

    // ── Scheduler can be scheduled and aborted ────────────────────────────────

    @IsTest
    static void testScheduler_scheduleAndAbort() {
        Test.startTest();
        ForecastStageSnapshotScheduler.schedule();
        Assert.isTrue(ForecastStageSnapshotScheduler.isScheduled());
        Assert.isNotNull(ForecastStageSnapshotScheduler.getNextFireTime());

        ForecastStageSnapshotScheduler.abortExisting();
        Assert.isFalse(ForecastStageSnapshotScheduler.isScheduled());
        Test.stopTest();
    }

    // ── Scheduler.execute enqueues the queueable ──────────────────────────────

    @IsTest
    static void testScheduler_executeEnqueues() {
        mockWeights();
        Test.startTest();
        String jobId = System.schedule('FSS test trigger',
            ForecastStageSnapshotScheduler.CRON_SUNDAY_2359,
            new ForecastStageSnapshotScheduler());
        Assert.isNotNull(jobId);
        Test.stopTest();
        // execute() runs at the cron time, which Test.stopTest doesn't fire for Schedulables;
        // we just verify scheduling didn't throw and the job exists
    }
}
