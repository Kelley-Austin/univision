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

        // Standard Opportunity FiscalYear is read-only and derived from CloseDate.
        Opportunity opp = new Opportunity(
            Name      = 'Q1 Buy',
            AccountId = adv.Id,
            StageName = 'Working',
            CloseDate = Date.newInstance(2026, 3, 31)
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
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

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
        Opportunity opp = new Opportunity(
            Name      = 'Empty Opp',
            AccountId = adv2.Id,
            StageName = 'Working',
            CloseDate = Date.newInstance(2026, 3, 31)
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
        // AccountId intentionally null to exercise the "no Account" branch.
        Opportunity opp = new Opportunity(
            Name      = 'Orphan Opp',
            StageName = 'Working',
            CloseDate = Date.today().addDays(30)
        );
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
