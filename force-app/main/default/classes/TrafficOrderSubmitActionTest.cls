@IsTest
private class TrafficOrderSubmitActionTest {

    @TestSetup
    static void setupData() {
        Account acct = new Account(Name = 'Test Advertiser');
        insert acct;

        Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
            Account__c = acct.Id,
            Status__c = 'Active'
        );
        insert opp;

        Advertising_Contract__c contract = new Advertising_Contract__c(
            Advertising_Opportunity__c = opp.Id,
            Contract_Status__c = 'Active'
        );
        insert contract;

        Channel__c channel = new Channel__c(
            Name = 'Test Channel',
            Channel_Code__c = 'TC-001'
        );
        insert channel;

        Budget_Line__c line = new Budget_Line__c(
            Advertising_Opportunity__c = opp.Id,
            Channel__c = channel.Id,
            Account__c = acct.Id,
            Status__c = 'Draft'
        );
        insert line;
    }

    @IsTest
    static void testSubmitSetsLinePendingAndEnqueuesJob() {
        Budget_Line__c line = [SELECT Id FROM Budget_Line__c LIMIT 1];

        TrafficOrderSubmitAction.Request req = new TrafficOrderSubmitAction.Request();
        req.budgetLineId = line.Id;
        req.copyCode = 'CP-001';
        req.copyRotation = '50/50';
        req.spotLength = ':30';
        req.weeklySpots = 5;
        req.spotRate = 1500.00;
        req.spotInstructions = 'Run in prime time only.';

        Test.startTest();
        List<TrafficOrderSubmitAction.Result> results =
            TrafficOrderSubmitAction.submit(new List<TrafficOrderSubmitAction.Request>{ req });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].success, 'Expected success=true');
        Assert.isNotNull(results[0].jobId, 'Expected a queued job ID');

        Budget_Line__c updated = [
            SELECT Traffic_Status__c, Copy_Code__c, Copy_Rotation__c,
                   Spot_Length__c, Weekly_Spots__c, Spot_Rate__c
            FROM Budget_Line__c
            WHERE Id = :line.Id
        ];
        Assert.areEqual('Pending', updated.Traffic_Status__c);
        Assert.areEqual('CP-001', updated.Copy_Code__c);
        Assert.areEqual('50/50', updated.Copy_Rotation__c);
        Assert.areEqual(':30', updated.Spot_Length__c);
        Assert.areEqual(5, updated.Weekly_Spots__c.intValue());
        Assert.areEqual(1500.00, updated.Spot_Rate__c);
    }

    @IsTest
    static void testSubmitSetsContractPending() {
        Budget_Line__c line = [SELECT Id FROM Budget_Line__c LIMIT 1];
        Advertising_Contract__c contract = [SELECT Id, Traffic_Status__c FROM Advertising_Contract__c LIMIT 1];

        TrafficOrderSubmitAction.Request req = new TrafficOrderSubmitAction.Request();
        req.budgetLineId = line.Id;
        req.copyCode = 'CP-002';

        Test.startTest();
        List<TrafficOrderSubmitAction.Result> results =
            TrafficOrderSubmitAction.submit(new List<TrafficOrderSubmitAction.Request>{ req });
        Test.stopTest();

        Assert.isTrue(results[0].success);

        Advertising_Contract__c updated = [
            SELECT Traffic_Status__c FROM Advertising_Contract__c WHERE Id = :contract.Id
        ];
        Assert.areEqual('Pending', updated.Traffic_Status__c);
    }

    @IsTest
    static void testSubmitWithNoLinkedOpportunity() {
        // Budget line with no opportunity — contract lookup should be skipped gracefully
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Channel__c channel = [SELECT Id FROM Channel__c LIMIT 1];

        Budget_Line__c orphanLine = new Budget_Line__c(
            Channel__c = channel.Id,
            Account__c = acct.Id,
            Status__c = 'Draft'
        );
        insert orphanLine;

        TrafficOrderSubmitAction.Request req = new TrafficOrderSubmitAction.Request();
        req.budgetLineId = orphanLine.Id;
        req.copyCode = 'CP-003';

        Test.startTest();
        List<TrafficOrderSubmitAction.Result> results =
            TrafficOrderSubmitAction.submit(new List<TrafficOrderSubmitAction.Request>{ req });
        Test.stopTest();

        Assert.isTrue(results[0].success, 'Should succeed even without a linked opportunity');
        Budget_Line__c updated = [SELECT Traffic_Status__c FROM Budget_Line__c WHERE Id = :orphanLine.Id];
        Assert.areEqual('Pending', updated.Traffic_Status__c);
    }

    @IsTest
    static void testSubmitWithInvalidLineId() {
        // Fabricate an Id-shaped string for a non-existent record
        Id fakeId = Budget_Line__c.sObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';

        TrafficOrderSubmitAction.Request req = new TrafficOrderSubmitAction.Request();
        req.budgetLineId = fakeId;
        req.copyCode = 'CP-FAKE';

        List<TrafficOrderSubmitAction.Result> results =
            TrafficOrderSubmitAction.submit(new List<TrafficOrderSubmitAction.Request>{ req });

        Assert.isFalse(results[0].success);
        Assert.isTrue(results[0].errorMessage.contains('not found'));
    }

    @IsTest
    static void testCancelledContractSkipped() {
        Advertising_Contract__c contract = [SELECT Id FROM Advertising_Contract__c LIMIT 1];
        contract.Contract_Status__c = 'Cancelled';
        update contract;

        Budget_Line__c line = [SELECT Id FROM Budget_Line__c LIMIT 1];

        TrafficOrderSubmitAction.Request req = new TrafficOrderSubmitAction.Request();
        req.budgetLineId = line.Id;
        req.copyCode = 'CP-CANCEL';

        Test.startTest();
        List<TrafficOrderSubmitAction.Result> results =
            TrafficOrderSubmitAction.submit(new List<TrafficOrderSubmitAction.Request>{ req });
        Test.stopTest();

        // The line should still submit successfully; cancelled contract is just not updated
        Assert.isTrue(results[0].success);
        Advertising_Contract__c unchanged = [
            SELECT Traffic_Status__c FROM Advertising_Contract__c WHERE Id = :contract.Id
        ];
        Assert.areNotEqual('Pending', unchanged.Traffic_Status__c);
    }
}
