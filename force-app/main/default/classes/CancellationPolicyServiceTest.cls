@IsTest
private class CancellationPolicyServiceTest {

    // Assumes Advertising_Opportunity__c (from the budget-planning slice) exists in the org.

    @TestSetup
    static void makeData() {
        Account acct = new Account(Name = 'Test Advertiser');
        insert acct;

        Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
            Account__c = acct.Id,
            Status__c = 'Draft'
        );
        insert opp;

        List<Advertising_Contract__c> contracts = new List<Advertising_Contract__c>{
            // Standard 30-Day — start 60 days out, notice IS met (60 >= 30)
            new Advertising_Contract__c(
                Advertising_Opportunity__c = opp.Id,
                Contract_Status__c = 'Active',
                Cancellation_Policy__c = 'Standard 30-Day',
                Total_Contract_Value__c = 100000,
                Start_Date__c = Date.today().addDays(60)
            ),
            // Standard 30-Day — start 10 days out, notice NOT met (10 < 30), fee = 30%
            new Advertising_Contract__c(
                Advertising_Opportunity__c = opp.Id,
                Contract_Status__c = 'Active',
                Cancellation_Policy__c = 'Standard 30-Day',
                Total_Contract_Value__c = 50000,
                Start_Date__c = Date.today().addDays(10)
            ),
            // Standard 60-Day — start 45 days out, notice NOT met (45 < 60), fee = 60%
            new Advertising_Contract__c(
                Advertising_Opportunity__c = opp.Id,
                Contract_Status__c = 'Active',
                Cancellation_Policy__c = 'Standard 60-Day',
                Total_Contract_Value__c = 120000,
                Start_Date__c = Date.today().addDays(45)
            ),
            // Non-Cancellable
            new Advertising_Contract__c(
                Advertising_Opportunity__c = opp.Id,
                Contract_Status__c = 'Active',
                Cancellation_Policy__c = 'Non-Cancellable',
                Total_Contract_Value__c = 75000,
                Start_Date__c = Date.today().addDays(90)
            ),
            // Custom — 45 days notice required, 25% fee, start 30 days out → notice NOT met
            new Advertising_Contract__c(
                Advertising_Opportunity__c = opp.Id,
                Contract_Status__c = 'Active',
                Cancellation_Policy__c = 'Custom',
                Cancellation_Notice_Days__c = 45,
                Cancellation_Fee_Percent__c = 25,
                Total_Contract_Value__c = 200000,
                Make_Good_Credits__c = 1000,
                Start_Date__c = Date.today().addDays(30)
            )
        };
        insert contracts;
    }

    @IsTest
    static void testMakeGoodAddsCredit() {
        Advertising_Contract__c contract = [
            SELECT Id, Make_Good_Credits__c
            FROM Advertising_Contract__c
            WHERE Cancellation_Policy__c = 'Custom'
            LIMIT 1
        ];

        CancellationPolicyService.Request req = new CancellationPolicyService.Request();
        req.contractId = contract.Id;
        req.requestType = 'Make Good';
        req.reason = 'Underdelivery on Q1 campaign';
        req.requestedCreditAmount = 5000;

        Test.startTest();
        List<CancellationPolicyService.Result> results =
            CancellationPolicyService.process(new List<CancellationPolicyService.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one result');
        System.assertEquals(true, results[0].success, 'Make-good should succeed');

        Advertising_Contract__c updated = [SELECT Make_Good_Credits__c FROM Advertising_Contract__c WHERE Id = :contract.Id];
        System.assertEquals(6000, updated.Make_Good_Credits__c, 'Credits should be 1000 + 5000');
    }

    @IsTest
    static void testCancellationNoticePeriodMet_NoFee() {
        // 60 days until start, 30-day policy → notice met, no fee
        Advertising_Contract__c contract = [
            SELECT Id
            FROM Advertising_Contract__c
            WHERE Cancellation_Policy__c = 'Standard 30-Day'
            AND Total_Contract_Value__c = 100000
            LIMIT 1
        ];

        CancellationPolicyService.Request req = new CancellationPolicyService.Request();
        req.contractId = contract.Id;
        req.requestType = 'Cancellation';
        req.reason = 'Client budget reallocation';

        Test.startTest();
        List<CancellationPolicyService.Result> results =
            CancellationPolicyService.process(new List<CancellationPolicyService.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(true, results[0].noticePeriodMet);
        System.assertEquals(0, results[0].cancellationFeeAmount);
        System.assertEquals(30, results[0].requiredNoticeDays);

        Advertising_Contract__c updated = [SELECT Contract_Status__c FROM Advertising_Contract__c WHERE Id = :contract.Id];
        System.assertEquals('Cancelled', updated.Contract_Status__c);
    }

    @IsTest
    static void testCancellationNoticePeriodNotMet_FeeApplied() {
        // 10 days until start, 30-day policy → fee = 50000 * 30% = 15000
        Advertising_Contract__c contract = [
            SELECT Id
            FROM Advertising_Contract__c
            WHERE Cancellation_Policy__c = 'Standard 30-Day'
            AND Total_Contract_Value__c = 50000
            LIMIT 1
        ];

        CancellationPolicyService.Request req = new CancellationPolicyService.Request();
        req.contractId = contract.Id;
        req.requestType = 'Cancellation';
        req.reason = 'Client changed strategy';

        Test.startTest();
        List<CancellationPolicyService.Result> results =
            CancellationPolicyService.process(new List<CancellationPolicyService.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(false, results[0].noticePeriodMet);
        System.assertEquals(15000, results[0].cancellationFeeAmount, 'Fee should be 30% of 50000');
        System.assertEquals(30, results[0].effectiveFeePercent);

        Advertising_Contract__c updated = [
            SELECT Contract_Status__c, Cancellation_Fee_Amount__c, Cancellation_Fee_Percent__c, Cancellation_Request_Date__c
            FROM Advertising_Contract__c WHERE Id = :contract.Id
        ];
        System.assertEquals('Cancelled', updated.Contract_Status__c);
        System.assertEquals(15000, updated.Cancellation_Fee_Amount__c);
        System.assertEquals(30, updated.Cancellation_Fee_Percent__c);
        System.assertEquals(Date.today(), updated.Cancellation_Request_Date__c);
    }

    @IsTest
    static void testCancellationStandard60Day_FeeApplied() {
        // 45 days until start, 60-day policy → fee = 120000 * 60% = 72000
        Advertising_Contract__c contract = [
            SELECT Id
            FROM Advertising_Contract__c
            WHERE Cancellation_Policy__c = 'Standard 60-Day'
            LIMIT 1
        ];

        CancellationPolicyService.Request req = new CancellationPolicyService.Request();
        req.contractId = contract.Id;
        req.requestType = 'Cancellation';
        req.reason = 'Merger — advertiser acquired';

        Test.startTest();
        List<CancellationPolicyService.Result> results =
            CancellationPolicyService.process(new List<CancellationPolicyService.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(false, results[0].noticePeriodMet);
        System.assertEquals(72000, results[0].cancellationFeeAmount, 'Fee should be 60% of 120000');
        System.assertEquals(60, results[0].requiredNoticeDays);
    }

    @IsTest
    static void testNonCancellableBlocked() {
        Advertising_Contract__c contract = [
            SELECT Id
            FROM Advertising_Contract__c
            WHERE Cancellation_Policy__c = 'Non-Cancellable'
            LIMIT 1
        ];

        CancellationPolicyService.Request req = new CancellationPolicyService.Request();
        req.contractId = contract.Id;
        req.requestType = 'Cancellation';
        req.reason = 'Testing block';

        Test.startTest();
        List<CancellationPolicyService.Result> results =
            CancellationPolicyService.process(new List<CancellationPolicyService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Non-Cancellable should fail');
        System.assert(results[0].errorMessage != null && results[0].errorMessage.contains('Non-Cancellable'));

        // Status must be unchanged
        Advertising_Contract__c unchanged = [SELECT Contract_Status__c FROM Advertising_Contract__c WHERE Id = :contract.Id];
        System.assertEquals('Active', unchanged.Contract_Status__c, 'Status must not change for Non-Cancellable');
    }

    @IsTest
    static void testCustomPolicyFee() {
        // 30 days until start, 45-day notice required → NOT met; fee = 200000 * 25% = 50000
        Advertising_Contract__c contract = [
            SELECT Id
            FROM Advertising_Contract__c
            WHERE Cancellation_Policy__c = 'Custom'
            LIMIT 1
        ];

        CancellationPolicyService.Request req = new CancellationPolicyService.Request();
        req.contractId = contract.Id;
        req.requestType = 'Cancellation';
        req.reason = 'Custom policy cancellation test';

        Test.startTest();
        List<CancellationPolicyService.Result> results =
            CancellationPolicyService.process(new List<CancellationPolicyService.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(false, results[0].noticePeriodMet);
        System.assertEquals(50000, results[0].cancellationFeeAmount, 'Fee should be 25% of 200000');
        System.assertEquals(45, results[0].requiredNoticeDays);
    }

    @IsTest
    static void testMakeGoodWithNullCredit() {
        Advertising_Contract__c contract = [
            SELECT Id, Make_Good_Credits__c
            FROM Advertising_Contract__c
            WHERE Cancellation_Policy__c = 'Custom'
            LIMIT 1
        ];

        CancellationPolicyService.Request req = new CancellationPolicyService.Request();
        req.contractId = contract.Id;
        req.requestType = 'Make Good';
        req.reason = 'Null credit test';
        req.requestedCreditAmount = null;

        Test.startTest();
        List<CancellationPolicyService.Result> results =
            CancellationPolicyService.process(new List<CancellationPolicyService.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        Advertising_Contract__c updated = [SELECT Make_Good_Credits__c FROM Advertising_Contract__c WHERE Id = :contract.Id];
        System.assertEquals(1000, updated.Make_Good_Credits__c, 'Credits unchanged when null credit passed');
    }
}
