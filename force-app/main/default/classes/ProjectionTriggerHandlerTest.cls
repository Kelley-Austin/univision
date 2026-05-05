@IsTest
private class ProjectionTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        Id advRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();
        Account adv = new Account(Name = 'Forecast Stage Test Advertiser', RecordTypeId = advRtId);
        insert adv;

        Category__c cat = new Category__c(Name = 'Forecast Stage Test Category');
        insert cat;

        Projection__c proj = new Projection__c(
            Account__c        = adv.Id,
            Category__c       = cat.Id,
            Revenue_Type__c   = 'National TV',
            Period_Year__c    = 2026,
            Period_Month__c   = 6,
            Amount__c         = 1000,
            Stage__c          = 'Working',
            Forecast_Stage__c = 'Stage 2'
        );
        insert proj;
    }

    private static Projection__c reload() {
        return [SELECT Id, Forecast_Stage__c FROM Projection__c LIMIT 1];
    }

    // ── Forward transition is always allowed (no bypass needed) ───────────────

    @IsTest
    static void testForwardTransition_allowed() {
        ProjectionTriggerHandler.testBypassOverride = false;
        Projection__c p = reload();
        p.Forecast_Stage__c = 'Stage 4';

        Test.startTest();
        update p;
        Test.stopTest();

        Assert.areEqual('Stage 4', reload().Forecast_Stage__c);
    }

    // ── Regression is blocked without bypass ──────────────────────────────────

    @IsTest
    static void testRegression_blockedWithoutBypass() {
        ProjectionTriggerHandler.testBypassOverride = false;
        Projection__c p = reload();
        p.Forecast_Stage__c = 'Stage 1';

        Boolean threw = false;
        Test.startTest();
        try {
            update p;
        } catch (DmlException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Illegal forecast stage regression'),
                'Expected regression-block message; got: ' + e.getMessage());
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected DmlException for regression');
        Assert.areEqual('Stage 2', reload().Forecast_Stage__c, 'Stage should not have regressed');
    }

    // ── Bypass permission lets regression succeed ─────────────────────────────

    @IsTest
    static void testRegression_allowedWithBypass() {
        ProjectionTriggerHandler.testBypassOverride = true;
        Projection__c p = reload();
        p.Forecast_Stage__c = 'Stage 0';

        Test.startTest();
        update p;
        Test.stopTest();

        Assert.areEqual('Stage 0', reload().Forecast_Stage__c);
    }

    // ── NA → any stage and any stage → NA are allowed ─────────────────────────

    @IsTest
    static void testNA_transitionsAllowed() {
        ProjectionTriggerHandler.testBypassOverride = false;

        Projection__c p = reload();
        p.Forecast_Stage__c = 'NA';

        Test.startTest();
        update p;
        Assert.areEqual('NA', reload().Forecast_Stage__c, 'Any stage → NA should be allowed');

        p = reload();
        p.Forecast_Stage__c = 'Stage 0';
        update p;
        Assert.areEqual('Stage 0', reload().Forecast_Stage__c, 'NA → any stage should be allowed');
        Test.stopTest();
    }

    // ── Booked is the highest rank (any → Booked allowed; Booked → earlier blocked) ─

    @IsTest
    static void testBooked_isHighestRank() {
        ProjectionTriggerHandler.testBypassOverride = false;

        Projection__c p = reload();
        p.Forecast_Stage__c = 'Booked';
        Test.startTest();
        update p;
        Assert.areEqual('Booked', reload().Forecast_Stage__c);

        p = reload();
        p.Forecast_Stage__c = 'Stage 5';
        Boolean threw = false;
        try { update p; } catch (DmlException e) { threw = true; }
        Test.stopTest();

        Assert.isTrue(threw, 'Booked → Stage 5 should be blocked as regression');
        Assert.areEqual('Booked', reload().Forecast_Stage__c);
    }

    // ── Same-stage update is a no-op (no regression error) ────────────────────

    @IsTest
    static void testSameStage_noOp() {
        ProjectionTriggerHandler.testBypassOverride = false;
        Projection__c p = reload();
        p.Amount__c = 2000; // unrelated change, stage unchanged

        Test.startTest();
        update p;
        Test.stopTest();

        Assert.areEqual('Stage 2', reload().Forecast_Stage__c);
    }

    // ── buildCompositeKey continues to work for callers ───────────────────────

    @IsTest
    static void testBuildCompositeKey_smoke() {
        Account adv = [SELECT Id FROM Account LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c LIMIT 1];
        String key = ProjectionTriggerHandler.buildCompositeKey(new Projection__c(
            Account__c      = adv.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'National TV',
            Period_Year__c  = 2026,
            Period_Month__c = 6
        ));
        Assert.isTrue(key.contains('National TV|2026|6'));
    }
}
