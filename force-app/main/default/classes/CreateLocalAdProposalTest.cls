@IsTest
private class CreateLocalAdProposalTest {

    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Test Advertiser');
        insert acct;

        Channel__c ch = new Channel__c(
            Name = 'KUVN',
            Status__c = 'Active',
            Channel_Type__c = 'TV'
        );
        insert ch;

        Vehicle__c v = new Vehicle__c(
            Name = 'Gold Network',
            Status__c = 'Active',
            Day_Part__c = 'Prime',
            Rate_Card__c = 5000
        );
        insert v;

        Channel__c inactiveCh = new Channel__c(
            Name = 'INACTIVE-CH',
            Status__c = 'Inactive',
            Channel_Type__c = 'Radio'
        );
        insert inactiveCh;
    }

    @IsTest
    static void testCreateProposalHappyPath() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Advertiser' LIMIT 1];
        Channel__c ch = [SELECT Id FROM Channel__c WHERE Name = 'KUVN' LIMIT 1];
        Vehicle__c v  = [SELECT Id FROM Vehicle__c WHERE Name = 'Gold Network' LIMIT 1];

        String linesJson = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{
                'channelId'     => (String) ch.Id,
                'month'         => 'January',
                'fiscalYear'    => '2026',
                'plannedAmount' => 10000,
                'notes'         => 'Q1 spot package'
            }
        });

        CreateLocalAdProposal.ProposalRequest req = new CreateLocalAdProposal.ProposalRequest();
        req.accountId     = acct.Id;
        req.market        = 'Los Angeles';
        req.startDate     = Date.today();
        req.endDate       = Date.today().addMonths(3);
        req.primaryDemo   = 'A18-49';
        req.secondaryDemo = 'W25-54';
        req.proposalNotes = 'Q1 Campaign — local market push';
        req.totalBudget   = 50000;
        req.vehicleId     = v.Id;
        req.budgetLinesJson = linesJson;

        Test.startTest();
        List<CreateLocalAdProposal.ProposalResult> results =
            CreateLocalAdProposal.createProposal(
                new List<CreateLocalAdProposal.ProposalRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected 1 result');
        System.assertEquals(true, results[0].success, results[0].errorMessage);
        System.assertNotEquals(null, results[0].opportunityId);

        Opportunity opp = [
            SELECT Market__c, Primary_Demo__c, Secondary_Demo__c,
                   Total_Planned_Amount__c, Total_Budget__c, StageName
            FROM Opportunity
            WHERE Id = :results[0].opportunityId
        ];
        System.assertEquals('Los Angeles', opp.Market__c);
        System.assertEquals('A18-49', opp.Primary_Demo__c);
        System.assertEquals('W25-54', opp.Secondary_Demo__c);
        System.assertEquals(10000, opp.Total_Planned_Amount__c);
        System.assertEquals(50000, opp.Total_Budget__c);
        System.assertEquals('Stage 1 - Lead', opp.StageName);

        List<Budget_Line__c> lines = [
            SELECT Month__c, Planned_Amount__c, Vehicle__c, Channel__c
            FROM Budget_Line__c
            WHERE Opportunity__c = :results[0].opportunityId
        ];
        System.assertEquals(1, lines.size());
        System.assertEquals(10000, lines[0].Planned_Amount__c);
        System.assertEquals(v.Id,  lines[0].Vehicle__c);
        System.assertEquals(ch.Id, lines[0].Channel__c);
    }

    @IsTest
    static void testCreateProposalNoBudgetLines() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Advertiser' LIMIT 1];
        Vehicle__c v  = [SELECT Id FROM Vehicle__c WHERE Name = 'Gold Network' LIMIT 1];

        CreateLocalAdProposal.ProposalRequest req = new CreateLocalAdProposal.ProposalRequest();
        req.accountId   = acct.Id;
        req.market      = 'Miami';
        req.startDate   = Date.today();
        req.endDate     = Date.today().addMonths(1);
        req.totalBudget = 25000;
        req.vehicleId   = v.Id;

        Test.startTest();
        List<CreateLocalAdProposal.ProposalResult> results =
            CreateLocalAdProposal.createProposal(
                new List<CreateLocalAdProposal.ProposalRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success, results[0].errorMessage);

        List<Budget_Line__c> lines = [
            SELECT Id FROM Budget_Line__c
            WHERE Opportunity__c = :results[0].opportunityId
        ];
        System.assertEquals(0, lines.size(), 'Expected no budget lines');
    }

    @IsTest
    static void testCreateProposalEmptyJsonArrayNoBudgetLines() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Advertiser' LIMIT 1];
        Vehicle__c v  = [SELECT Id FROM Vehicle__c WHERE Name = 'Gold Network' LIMIT 1];

        CreateLocalAdProposal.ProposalRequest req = new CreateLocalAdProposal.ProposalRequest();
        req.accountId       = acct.Id;
        req.startDate       = Date.today();
        req.endDate         = Date.today().addMonths(1);
        req.vehicleId       = v.Id;
        req.budgetLinesJson = '[]';

        Test.startTest();
        List<CreateLocalAdProposal.ProposalResult> results =
            CreateLocalAdProposal.createProposal(
                new List<CreateLocalAdProposal.ProposalRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(0, [SELECT COUNT() FROM Budget_Line__c
                                  WHERE Opportunity__c = :results[0].opportunityId]);
    }

    @IsTest
    static void testCreateProposalMultipleBudgetLinesRollup() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Advertiser' LIMIT 1];
        Channel__c ch = [SELECT Id FROM Channel__c WHERE Name = 'KUVN' LIMIT 1];
        Vehicle__c v  = [SELECT Id FROM Vehicle__c WHERE Name = 'Gold Network' LIMIT 1];

        List<Map<String, Object>> lineData = new List<Map<String, Object>>();
        for (Integer i = 0; i < 4; i++) {
            lineData.add(new Map<String, Object>{
                'channelId'     => (String) ch.Id,
                'month'         => 'February',
                'fiscalYear'    => '2026',
                'plannedAmount' => 2500,
                'notes'         => ''
            });
        }

        CreateLocalAdProposal.ProposalRequest req = new CreateLocalAdProposal.ProposalRequest();
        req.accountId       = acct.Id;
        req.startDate       = Date.today();
        req.endDate         = Date.today().addMonths(3);
        req.vehicleId       = v.Id;
        req.budgetLinesJson = JSON.serialize(lineData);

        Test.startTest();
        List<CreateLocalAdProposal.ProposalResult> results =
            CreateLocalAdProposal.createProposal(
                new List<CreateLocalAdProposal.ProposalRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);

        Opportunity opp = [
            SELECT Total_Planned_Amount__c
            FROM Opportunity
            WHERE Id = :results[0].opportunityId
        ];
        System.assertEquals(10000, opp.Total_Planned_Amount__c, 'Rollup should total 4 × $2,500');
        System.assertEquals(4, [SELECT COUNT() FROM Budget_Line__c
                                  WHERE Opportunity__c = :results[0].opportunityId]);
    }

    @IsTest
    static void testCreateProposalNullAccountReturnsError() {
        CreateLocalAdProposal.ProposalRequest req = new CreateLocalAdProposal.ProposalRequest();
        req.accountId = null;
        req.startDate = Date.today();
        req.endDate   = Date.today().addMonths(1);

        Test.startTest();
        List<CreateLocalAdProposal.ProposalResult> results =
            CreateLocalAdProposal.createProposal(
                new List<CreateLocalAdProposal.ProposalRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Null required Account__c should fail');
        System.assertNotEquals(null, results[0].errorMessage);
        System.assertEquals(0, [SELECT COUNT() FROM Opportunity]);
    }

    @IsTest
    static void testBulkInvocation() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Advertiser' LIMIT 1];
        Vehicle__c v  = [SELECT Id FROM Vehicle__c WHERE Name = 'Gold Network' LIMIT 1];

        List<CreateLocalAdProposal.ProposalRequest> requests =
            new List<CreateLocalAdProposal.ProposalRequest>();
        for (Integer i = 0; i < 5; i++) {
            CreateLocalAdProposal.ProposalRequest req = new CreateLocalAdProposal.ProposalRequest();
            req.accountId = acct.Id;
            req.market    = 'Chicago';
            req.startDate = Date.today();
            req.endDate   = Date.today().addMonths(1);
            req.vehicleId = v.Id;
            requests.add(req);
        }

        Test.startTest();
        List<CreateLocalAdProposal.ProposalResult> results =
            CreateLocalAdProposal.createProposal(requests);
        Test.stopTest();

        System.assertEquals(5, results.size());
        for (CreateLocalAdProposal.ProposalResult r : results) {
            System.assertEquals(true, r.success, r.errorMessage);
        }
        System.assertEquals(5, [SELECT COUNT() FROM Opportunity]);
    }

    @IsTest
    static void testGetActiveChannels() {
        Test.startTest();
        List<Channel__c> channels = CreateLocalAdProposal.getActiveChannels();
        Test.stopTest();

        System.assertEquals(1, channels.size(), 'Only active channels should be returned');
        System.assertEquals('KUVN', channels[0].Name);
    }

    @IsTest
    static void testGetActiveVehicles() {
        Test.startTest();
        List<Vehicle__c> vehicles = CreateLocalAdProposal.getActiveVehicles();
        Test.stopTest();

        System.assertEquals(1, vehicles.size(), 'Only active vehicles should be returned');
        System.assertEquals('Gold Network', vehicles[0].Name);
        System.assertNotEquals(null, vehicles[0].Day_Part__c);
    }

    @IsTest
    static void testRecordTypeSetsCorrectly() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Advertiser' LIMIT 1];

        CreateLocalAdProposal.ProposalRequest req = new CreateLocalAdProposal.ProposalRequest();
        req.accountId = acct.Id;
        req.startDate = Date.today();
        req.endDate   = Date.today().addMonths(1);

        Test.startTest();
        List<CreateLocalAdProposal.ProposalResult> results =
            CreateLocalAdProposal.createProposal(
                new List<CreateLocalAdProposal.ProposalRequest>{ req }
            );
        Test.stopTest();

        Opportunity opp = [
            SELECT RecordType.DeveloperName
            FROM Opportunity
            WHERE Id = :results[0].opportunityId
        ];
        System.assertEquals('TV_Linear', opp.RecordType.DeveloperName);
    }
}
