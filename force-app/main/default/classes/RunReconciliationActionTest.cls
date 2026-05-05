@IsTest
private class RunReconciliationActionTest {

    @TestSetup
    static void setupData() {
        Id advRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();
        Account adv = new Account(
            Name             = 'Run Recon Test Advertiser',
            MDM_External_Id__c = 'RR-ADV-001',
            RecordTypeId     = advRtId
        );
        insert adv;

        Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
            Name           = 'Q1 Buy',
            Account__c     = adv.Id,
            Fiscal_Year__c = '2026'
        );
        insert opp;

        // Two Actual_Revenue__c records for this account in the opp's fiscal year
        insert new List<Actual_Revenue__c>{
            new Actual_Revenue__c(
                Account__c       = adv.Id,
                External_Key__c  = 'EXT-RR-001',
                Revenue_Amount__c = 1000,
                Revenue_Type__c  = 'National TV',
                Period_Year__c   = 2026,
                Period_Month__c  = 1
            ),
            new Actual_Revenue__c(
                Account__c       = adv.Id,
                External_Key__c  = 'EXT-RR-002',
                Revenue_Amount__c = 2000,
                Revenue_Type__c  = 'National TV',
                Period_Year__c   = 2026,
                Period_Month__c  = 2
            )
        };
    }

    @IsTest
    static void run_queuesRollupForMatchingActuals() {
        Advertising_Opportunity__c opp = [SELECT Id FROM Advertising_Opportunity__c LIMIT 1];

        RunReconciliationAction.ReconciliationRequest req = new RunReconciliationAction.ReconciliationRequest();
        req.opportunityId = opp.Id;

        Test.startTest();
        List<RunReconciliationAction.ReconciliationResult> results =
            RunReconciliationAction.run(new List<RunReconciliationAction.ReconciliationRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, 'Expected success: ' + results[0].message);
        System.assert(results[0].message.contains('2 Actual Revenue record'),
            'Expected message to mention 2 records: ' + results[0].message);
    }

    @IsTest
    static void run_returnsSuccessWithEmptyMessage_whenNoActuals() {
        Account adv2 = new Account(
            Name             = 'No Actuals Advertiser',
            MDM_External_Id__c = 'RR-ADV-002',
            RecordTypeId     = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId()
        );
        insert adv2;
        Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
            Name           = 'Empty Opp',
            Account__c     = adv2.Id,
            Fiscal_Year__c = '2026'
        );
        insert opp;

        RunReconciliationAction.ReconciliationRequest req = new RunReconciliationAction.ReconciliationRequest();
        req.opportunityId = opp.Id;

        Test.startTest();
        List<RunReconciliationAction.ReconciliationResult> results =
            RunReconciliationAction.run(new List<RunReconciliationAction.ReconciliationRequest>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assert(results[0].message.contains('Nothing to roll up'),
            'Expected nothing-to-roll-up message: ' + results[0].message);
    }

    @IsTest
    static void run_failsGracefully_whenAccountIsNull() {
        Advertising_Opportunity__c opp = new Advertising_Opportunity__c(Name = 'Orphan Opp');
        insert opp;

        RunReconciliationAction.ReconciliationRequest req = new RunReconciliationAction.ReconciliationRequest();
        req.opportunityId = opp.Id;

        Test.startTest();
        List<RunReconciliationAction.ReconciliationResult> results =
            RunReconciliationAction.run(new List<RunReconciliationAction.ReconciliationRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('no Account'),
            'Expected no-Account message: ' + results[0].message);
    }
}
