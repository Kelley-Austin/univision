@IsTest
private class DashboardEmailSchedulerTest {

    // ── Test Data ─────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Advertiser');
        insert acc;

        Channel__c ch = new Channel__c(Name = 'Test Channel');
        insert ch;

        Vehicle__c veh = new Vehicle__c(Name = 'Test Vehicle', Status__c = 'Active');
        insert veh;

        // Standard Opportunity FiscalYear is read-only and derived from CloseDate.
        Opportunity opp = new Opportunity(
            Name      = 'Dashboard Test Opp',
            AccountId = acc.Id,
            StageName = 'Active',
            Market__c = 'Los Angeles',
            CloseDate = Date.today()
        );
        insert opp;

        Budget_Line__c bl = new Budget_Line__c(
            Account__c       = acc.Id,
            Channel__c       = ch.Id,
            Vehicle__c       = veh.Id,
            Status__c        = 'Approved',
            Fiscal_Year__c   = Date.today().year(),
            Planned_Amount__c = 100000,
            Actual_Amount__c  = 85000
        );
        insert bl;

        Advertising_Contract__c contract = new Advertising_Contract__c(
            Opportunity__c   = opp.Id,
            Account__c       = acc.Id,
            Contract_Status__c = 'Active',
            Traffic_Status__c = 'Pending',
            Start_Date__c    = Date.today(),
            End_Date__c      = Date.today().addMonths(6)
        );
        insert contract;
    }

    // ── Scheduling ────────────────────────────────────────────────────────────

    @IsTest
    static void testScheduleSalesManager() {
        Test.startTest();
        DashboardEmailScheduler.scheduleSalesManager();
        Test.stopTest();

        System.assert(
            DashboardEmailScheduler.isSalesManagerScheduled(),
            'Sales Manager job should be scheduled'
        );
    }

    @IsTest
    static void testScheduleWeeklyAnalytics() {
        Test.startTest();
        DashboardEmailScheduler.scheduleWeeklyAnalytics();
        Test.stopTest();

        System.assert(
            DashboardEmailScheduler.isWeeklyAnalyticsScheduled(),
            'Weekly Analytics job should be scheduled'
        );
    }

    @IsTest
    static void testAbortExisting() {
        DashboardEmailScheduler.scheduleSalesManager();
        DashboardEmailScheduler.abortExisting(DashboardEmailScheduler.SALES_MANAGER_JOB);

        System.assert(
            !DashboardEmailScheduler.isSalesManagerScheduled(),
            'Job should be aborted'
        );
    }

    @IsTest
    static void testRescheduleClearsOldJob() {
        DashboardEmailScheduler.scheduleSalesManager();
        DashboardEmailScheduler.scheduleSalesManager();

        List<CronTrigger> cts = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :DashboardEmailScheduler.SALES_MANAGER_JOB
            AND State NOT IN ('DELETED', 'COMPLETE')
        ];
        System.assertEquals(1, cts.size(), 'Exactly one scheduled job should exist after re-schedule');
    }

    // ── Email Body — Sales Manager ─────────────────────────────────────────

    @IsTest
    static void testBuildSalesManagerBody_withData() {
        String body = DashboardEmailScheduler.buildSalesManagerBody();

        System.assert(body.contains('Sales Manager Dashboard'), 'Should contain title');
        System.assert(body.contains('Pipeline by Market'),      'Should contain pipeline section');
        System.assert(body.contains('Rep YTD Performance'),     'Should contain rep section');
        System.assert(body.contains('Active Pipeline by Stage'), 'Should contain aging section');
        System.assert(body.contains('Los Angeles'),             'Should show market from test data');
    }

    @IsTest
    static void testBuildSalesManagerBody_empty() {
        // Delete setup data so body renders empty-state messages
        delete [SELECT Id FROM Opportunity];

        String body = DashboardEmailScheduler.buildSalesManagerBody();
        System.assert(body.contains('No active pipeline'), 'Should render empty pipeline state');
        System.assert(body.contains('No data'),            'Should render empty rep state');
        System.assert(body.contains('No active deals'),    'Should render empty aging state');
    }

    // ── Email Body — Weekly Analytics ──────────────────────────────────────

    @IsTest
    static void testBuildWeeklyAnalyticsBody_withData() {
        String body = DashboardEmailScheduler.buildWeeklyAnalyticsBody();

        System.assert(body.contains('Weekly Analytics Dashboard'),          'Should contain title');
        System.assert(body.contains('Budget vs. Actuals Pacing by Vehicle'), 'Should contain vehicle section');
        System.assert(body.contains('Budget vs. Actuals Pacing by Channel'), 'Should contain channel section');
        System.assert(body.contains('Revenue by Market'),                    'Should contain market section');
        System.assert(body.contains('Order Pacing by Traffic Status'),       'Should contain order section');
    }

    @IsTest
    static void testBuildWeeklyAnalyticsBody_empty() {
        delete [SELECT Id FROM Budget_Line__c];
        delete [SELECT Id FROM Advertising_Contract__c];
        delete [SELECT Id FROM Opportunity];

        String body = DashboardEmailScheduler.buildWeeklyAnalyticsBody();
        System.assert(body.contains('No vehicle data'),   'Should render empty vehicle state');
        System.assert(body.contains('No channel data'),   'Should render empty channel state');
        System.assert(body.contains('No active orders'),  'Should render empty orders state');
    }

    // ── sendSalesManagerDigest / sendWeeklyAnalyticsDigest ────────────────────

    @IsTest
    static void testSendSalesManagerDigest_withRecipients() {
        DashboardEmailScheduler.overrideRecipients = new List<String>{ 'test@example.com' };

        Test.startTest();
        DashboardEmailScheduler sched = new DashboardEmailScheduler(DashboardEmailScheduler.TYPE_SALES_MANAGER);
        sched.sendSalesManagerDigest();
        Test.stopTest();
        // Verifies: no exception thrown; email send limit not exceeded in test context
    }

    @IsTest
    static void testSendWeeklyAnalyticsDigest_withRecipients() {
        DashboardEmailScheduler.overrideRecipients = new List<String>{ 'test@example.com' };

        Test.startTest();
        DashboardEmailScheduler sched = new DashboardEmailScheduler(DashboardEmailScheduler.TYPE_WEEKLY_ANALYTICS);
        sched.sendWeeklyAnalyticsDigest();
        Test.stopTest();
    }

    @IsTest
    static void testSendSalesManagerDigest_noRecipients() {
        // With empty override, early-exit path is exercised without attempting sendEmail
        DashboardEmailScheduler.overrideRecipients = new List<String>();

        Test.startTest();
        DashboardEmailScheduler sched = new DashboardEmailScheduler(DashboardEmailScheduler.TYPE_SALES_MANAGER);
        sched.sendSalesManagerDigest();
        Test.stopTest();
    }

    @IsTest
    static void testSendWeeklyAnalyticsDigest_noRecipients() {
        DashboardEmailScheduler.overrideRecipients = new List<String>();

        Test.startTest();
        DashboardEmailScheduler sched = new DashboardEmailScheduler(DashboardEmailScheduler.TYPE_WEEKLY_ANALYTICS);
        sched.sendWeeklyAnalyticsDigest();
        Test.stopTest();
    }

    // ── execute() dispatch ────────────────────────────────────────────────────

    @IsTest
    static void testExecute_salesManager() {
        DashboardEmailScheduler.overrideRecipients = new List<String>{ 'test@example.com' };

        Test.startTest();
        System.schedule(
            'TEST_SM_' + System.currentTimeMillis(),
            '0 0 7 ? * MON',
            new DashboardEmailScheduler(DashboardEmailScheduler.TYPE_SALES_MANAGER)
        );
        Test.stopTest();
    }

    @IsTest
    static void testExecute_weeklyAnalytics() {
        DashboardEmailScheduler.overrideRecipients = new List<String>{ 'test@example.com' };

        Test.startTest();
        System.schedule(
            'TEST_WA_' + System.currentTimeMillis(),
            '0 0 16 ? * FRI',
            new DashboardEmailScheduler(DashboardEmailScheduler.TYPE_WEEKLY_ANALYTICS)
        );
        Test.stopTest();
    }

    // ── Pacing row — negative variance (red path) ─────────────────────────────

    @IsTest
    static void testWeeklyBody_negativeVarianceColors() {
        // Set actual below planned to trigger red variance rendering
        Budget_Line__c bl = [SELECT Id, Actual_Amount__c FROM Budget_Line__c LIMIT 1];
        bl.Actual_Amount__c = 0;
        update bl;

        String body = DashboardEmailScheduler.buildWeeklyAnalyticsBody();
        System.assert(body.contains('color:red'), 'Negative variance should render in red');
    }
}
