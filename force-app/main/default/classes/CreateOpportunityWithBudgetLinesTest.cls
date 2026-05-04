@isTest
public class CreateOpportunityWithBudgetLinesTest {

    @TestSetup
    static void makeData() {
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        Channel__c channel = new Channel__c(
            Name = 'WUNI-TV',
            Channel_Type__c = 'TV',
            Status__c = 'Active',
            Channel_Code__c = 'WUNI'
        );
        insert channel;
    }

    @isTest
    static void testHappyPath() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Channel__c chan = [SELECT Id FROM Channel__c LIMIT 1];

        String budgetLinesJson = '[{"channelId":"' + chan.Id + '",'
            + '"month":"January","fiscalYear":"FY2026","plannedAmount":5000,"notes":"Test note"}]';

        CreateOpportunityWithBudgetLines.OpportunityRequest req = new CreateOpportunityWithBudgetLines.OpportunityRequest();
        req.accountId    = acct.Id;
        req.startDate    = Date.today();
        req.endDate      = Date.today().addMonths(3);
        req.market       = 'Miami';
        req.fiscalYear   = 'FY2026';
        req.totalBudget  = 10000;
        req.budgetLinesJson = budgetLinesJson;

        Test.startTest();
        List<CreateOpportunityWithBudgetLines.OpportunityResult> results =
            CreateOpportunityWithBudgetLines.createOpportunityWithBudgetLines(
                new List<CreateOpportunityWithBudgetLines.OpportunityRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].isSuccess, 'Should succeed');
        System.assertNotEquals(null, results[0].opportunityId);

        Advertising_Opportunity__c opp = [
            SELECT Id, Status__c, Total_Planned_Amount__c
            FROM Advertising_Opportunity__c
            WHERE Id = :results[0].opportunityId
        ];
        System.assertEquals('Draft', opp.Status__c);
        System.assertEquals(5000, opp.Total_Planned_Amount__c);

        List<Budget_Line__c> lines = [
            SELECT Channel__c, Month__c, Planned_Amount__c, Status__c
            FROM Budget_Line__c
            WHERE Advertising_Opportunity__c = :opp.Id
        ];
        System.assertEquals(1, lines.size());
        System.assertEquals(chan.Id, lines[0].Channel__c);
        System.assertEquals('January', lines[0].Month__c);
        System.assertEquals(5000, lines[0].Planned_Amount__c);
        System.assertEquals('Draft', lines[0].Status__c);
    }

    @isTest
    static void testEmptyBudgetLines() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        CreateOpportunityWithBudgetLines.OpportunityRequest req = new CreateOpportunityWithBudgetLines.OpportunityRequest();
        req.accountId       = acct.Id;
        req.startDate       = Date.today();
        req.budgetLinesJson = '[]';

        Test.startTest();
        List<CreateOpportunityWithBudgetLines.OpportunityResult> results =
            CreateOpportunityWithBudgetLines.createOpportunityWithBudgetLines(
                new List<CreateOpportunityWithBudgetLines.OpportunityRequest>{ req }
            );
        Test.stopTest();

        System.assert(results[0].isSuccess, 'Should succeed with no lines');
        System.assertNotEquals(null, results[0].opportunityId);

        Integer lineCount = [SELECT COUNT() FROM Budget_Line__c WHERE Advertising_Opportunity__c = :results[0].opportunityId];
        System.assertEquals(0, lineCount);
    }

    @isTest
    static void testNullBudgetLinesJson() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        CreateOpportunityWithBudgetLines.OpportunityRequest req = new CreateOpportunityWithBudgetLines.OpportunityRequest();
        req.accountId       = acct.Id;
        req.startDate       = Date.today();
        req.budgetLinesJson = null;

        Test.startTest();
        List<CreateOpportunityWithBudgetLines.OpportunityResult> results =
            CreateOpportunityWithBudgetLines.createOpportunityWithBudgetLines(
                new List<CreateOpportunityWithBudgetLines.OpportunityRequest>{ req }
            );
        Test.stopTest();

        System.assert(results[0].isSuccess, 'Should succeed with null JSON');
    }

    @isTest
    static void testDefaultStatusDraft() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        CreateOpportunityWithBudgetLines.OpportunityRequest req = new CreateOpportunityWithBudgetLines.OpportunityRequest();
        req.accountId = acct.Id;
        req.startDate = Date.today();
        req.status    = null;

        Test.startTest();
        List<CreateOpportunityWithBudgetLines.OpportunityResult> results =
            CreateOpportunityWithBudgetLines.createOpportunityWithBudgetLines(
                new List<CreateOpportunityWithBudgetLines.OpportunityRequest>{ req }
            );
        Test.stopTest();

        Advertising_Opportunity__c opp = [
            SELECT Status__c FROM Advertising_Opportunity__c WHERE Id = :results[0].opportunityId
        ];
        System.assertEquals('Draft', opp.Status__c);
    }

    @isTest
    static void testErrorAndRollback() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        // Malformed JSON forces a JSONException, triggering rollback before any DML commits
        CreateOpportunityWithBudgetLines.OpportunityRequest req = new CreateOpportunityWithBudgetLines.OpportunityRequest();
        req.accountId       = acct.Id;
        req.startDate       = Date.today();
        req.budgetLinesJson = '[not-valid-json}}}';

        Test.startTest();
        List<CreateOpportunityWithBudgetLines.OpportunityResult> results =
            CreateOpportunityWithBudgetLines.createOpportunityWithBudgetLines(
                new List<CreateOpportunityWithBudgetLines.OpportunityRequest>{ req }
            );
        Test.stopTest();

        System.assert(!results[0].isSuccess, 'Should fail');
        System.assertNotEquals(null, results[0].errorMessage);

        Integer oppCount = [SELECT COUNT() FROM Advertising_Opportunity__c];
        System.assertEquals(0, oppCount, 'Rollback should have removed the opportunity');
    }

    @isTest
    static void testGetActiveChannels() {
        Test.startTest();
        List<Channel__c> channels = CreateOpportunityWithBudgetLines.getActiveChannels();
        Test.stopTest();

        System.assertEquals(1, channels.size());
        System.assertEquals('WUNI-TV', channels[0].Name);
    }

    @isTest
    static void testBulkInvocable() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Channel__c chan = [SELECT Id FROM Channel__c LIMIT 1];

        List<CreateOpportunityWithBudgetLines.OpportunityRequest> reqs = new List<CreateOpportunityWithBudgetLines.OpportunityRequest>();
        for (Integer i = 0; i < 5; i++) {
            CreateOpportunityWithBudgetLines.OpportunityRequest req = new CreateOpportunityWithBudgetLines.OpportunityRequest();
            req.accountId       = acct.Id;
            req.startDate       = Date.today().addMonths(i);
            req.budgetLinesJson = '[{"channelId":"' + chan.Id + '",'
                + '"month":"February","fiscalYear":"FY2026","plannedAmount":' + (1000 * (i + 1)) + ',"notes":""}]';
            reqs.add(req);
        }

        Test.startTest();
        List<CreateOpportunityWithBudgetLines.OpportunityResult> results =
            CreateOpportunityWithBudgetLines.createOpportunityWithBudgetLines(reqs);
        Test.stopTest();

        System.assertEquals(5, results.size());
        for (CreateOpportunityWithBudgetLines.OpportunityResult r : results) {
            System.assert(r.isSuccess, 'All bulk creates should succeed');
        }
        System.assertEquals(5, [SELECT COUNT() FROM Advertising_Opportunity__c]);
        System.assertEquals(5, [SELECT COUNT() FROM Budget_Line__c]);
    }
}
