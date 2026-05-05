@IsTest
private class ProjectionRollupQueueableTest {

    @TestSetup
    static void setupData() {
        Id advRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();
        Account adv = new Account(Name = 'Rollup Test Advertiser', RecordTypeId = advRtId);
        insert adv;

        Category__c cat = new Category__c(Name = 'National Spot');
        insert cat;

        // Two Actual_Revenue__c records for same grain
        List<Actual_Revenue__c> actuals = new List<Actual_Revenue__c>{
            new Actual_Revenue__c(
                Account__c        = adv.Id,
                Category__c       = cat.Id,
                Revenue_Type__c   = 'National TV',
                Period_Month__c   = 4,
                Period_Year__c    = 2026,
                Revenue_Amount__c = 1000,
                External_Key__c   = 'EXT-ROLLUP-001'
            ),
            new Actual_Revenue__c(
                Account__c        = adv.Id,
                Category__c       = cat.Id,
                Revenue_Type__c   = 'National TV',
                Period_Month__c   = 4,
                Period_Year__c    = 2026,
                Revenue_Amount__c = 500,
                External_Key__c   = 'EXT-ROLLUP-002'
            )
        };
        insert actuals;
    }

    // ── rollup() aggregates onto existing Projection__c ───────────────────────

    @IsTest
    static void testRollup_updatesExistingProjection() {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Rollup Test Advertiser' LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c WHERE Name = 'National Spot' LIMIT 1];

        // Pre-create a Projection record
        Projection__c proj = new Projection__c(
            Account__c      = adv.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'National TV',
            Period_Year__c  = 2026,
            Period_Month__c = 4,
            Amount__c       = 2000,
            Stage__c        = 'Working'
        );
        proj.Composite_Key__c = ProjectionTriggerHandler.buildCompositeKey(proj);
        insert proj;

        List<Actual_Revenue__c> actuals = [SELECT Id FROM Actual_Revenue__c];
        List<Id> ids = new List<Id>();
        for (Actual_Revenue__c a : actuals) ids.add(a.Id);

        Test.startTest();
        ProjectionRollupQueueable.rollup(ids);
        Test.stopTest();

        proj = [SELECT Actual_Amount__c FROM Projection__c WHERE Id = :proj.Id];
        Assert.areEqual(1500, proj.Actual_Amount__c, 'Expected sum of 1000 + 500 = 1500');
    }

    // ── rollup() creates stub Projection when none exists ─────────────────────

    @IsTest
    static void testRollup_createsStubProjection() {
        List<Actual_Revenue__c> actuals = [SELECT Id FROM Actual_Revenue__c];
        List<Id> ids = new List<Id>();
        for (Actual_Revenue__c a : actuals) ids.add(a.Id);

        Test.startTest();
        ProjectionRollupQueueable.rollup(ids);
        Test.stopTest();

        List<Projection__c> projs = [
            SELECT Actual_Amount__c, Amount__c
            FROM Projection__c
            WHERE Revenue_Type__c = 'National TV' AND Period_Month__c = 4
        ];
        Assert.isFalse(projs.isEmpty(), 'Expected stub Projection to be created');
        Assert.areEqual(1500, projs[0].Actual_Amount__c);
        Assert.areEqual(0, projs[0].Amount__c, 'Stub Amount__c should be 0');
    }

    // ── Queueable execute chains correctly for large sets ─────────────────────

    @IsTest
    static void testQueueable_execute() {
        List<Actual_Revenue__c> actuals = [SELECT Id FROM Actual_Revenue__c];
        Set<Id> ids = new Set<Id>();
        for (Actual_Revenue__c a : actuals) ids.add(a.Id);

        Test.startTest();
        System.enqueueJob(new ProjectionRollupQueueable(ids));
        Test.stopTest();

        List<Projection__c> projs = [SELECT Actual_Amount__c FROM Projection__c];
        Assert.isFalse(projs.isEmpty());
    }

    // ── Empty list ────────────────────────────────────────────────────────────

    @IsTest
    static void testRollup_emptyList() {
        ProjectionRollupQueueable.rollup(new List<Id>());
        Assert.areEqual(0, [SELECT COUNT() FROM Projection__c]);
    }

    // ── Superseded preempt is excluded from rollup sum ────────────────────────

    @IsTest
    static void testRollup_excludesSupersededPreempt() {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Rollup Test Advertiser' LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c WHERE Name = 'National Spot' LIMIT 1];

        // Preempt that has been Superseded — should NOT contribute to Actual_Amount__c
        Actual_Revenue__c superseded = new Actual_Revenue__c(
            Account__c             = adv.Id,
            Category__c            = cat.Id,
            Revenue_Type__c        = 'National TV',
            Period_Month__c        = 4,
            Period_Year__c         = 2026,
            Revenue_Amount__c      = 9999,
            External_Key__c        = 'EXT-ROLLUP-SS',
            Is_Preempt__c          = true,
            Preempt_Status__c      = 'Superseded',
            Source_Order_Number__c = 'ORD-RT'
        );
        insert superseded;

        List<Id> ids = new List<Id>();
        for (Actual_Revenue__c a : [SELECT Id FROM Actual_Revenue__c]) ids.add(a.Id);

        Test.startTest();
        ProjectionRollupQueueable.rollup(ids);
        Test.stopTest();

        Projection__c proj = [
            SELECT Actual_Amount__c FROM Projection__c
            WHERE Account__c = :adv.Id AND Category__c = :cat.Id
              AND Period_Year__c = 2026 AND Period_Month__c = 4
            LIMIT 1
        ];
        Assert.areEqual(1500, proj.Actual_Amount__c,
            'Rollup should sum 1000 + 500 from active actuals and exclude the 9999 Superseded preempt');
    }

    // ── Cancelled preempt is excluded from rollup sum ─────────────────────────

    @IsTest
    static void testRollup_excludesCancelledPreempt() {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Rollup Test Advertiser' LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c WHERE Name = 'National Spot' LIMIT 1];

        Actual_Revenue__c cancelled = new Actual_Revenue__c(
            Account__c             = adv.Id,
            Category__c            = cat.Id,
            Revenue_Type__c        = 'National TV',
            Period_Month__c        = 4,
            Period_Year__c         = 2026,
            Revenue_Amount__c      = 7777,
            External_Key__c        = 'EXT-ROLLUP-CXL',
            Is_Preempt__c          = true,
            Preempt_Status__c      = 'Cancelled',
            Source_Order_Number__c = 'ORD-RT'
        );
        insert cancelled;

        List<Id> ids = new List<Id>();
        for (Actual_Revenue__c a : [SELECT Id FROM Actual_Revenue__c]) ids.add(a.Id);

        Test.startTest();
        ProjectionRollupQueueable.rollup(ids);
        Test.stopTest();

        Projection__c proj = [
            SELECT Actual_Amount__c FROM Projection__c
            WHERE Account__c = :adv.Id AND Category__c = :cat.Id
              AND Period_Year__c = 2026 AND Period_Month__c = 4
            LIMIT 1
        ];
        Assert.areEqual(1500, proj.Actual_Amount__c,
            'Rollup should exclude Cancelled preempts');
    }
}
