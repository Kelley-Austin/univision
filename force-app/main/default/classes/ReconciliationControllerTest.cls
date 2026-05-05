@IsTest
private class ReconciliationControllerTest {

    @TestSetup
    static void setupData() {
        Id advRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();
        Account adv = new Account(
            Name             = 'Controller Test Advertiser',
            MDM_External_Id__c = 'CTRL-ADV-001',
            RecordTypeId     = advRtId
        );
        insert adv;

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User aeUser = new User(
            FirstName   = 'AE',
            LastName    = 'Controller',
            Email       = 'ae.ctrl@example.com',
            Username    = 'ae.ctrl@example.com.unittest',
            Alias       = 'AECTL',
            AE_Code__c  = 'AE200',
            ProfileId   = p.Id,
            TimeZoneSidKey    = 'America/Chicago',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert aeUser;

        Source_System__c ss = new Source_System__c(
            Name                 = 'WO Controller',
            Code__c              = 'WOCTRL',
            Source_Code__c       = 'WOCTRL',
            Transformer_Class__c = 'WideOrbitTransformer'
        );
        insert ss;

        Inbound_Staging__c stg = new Inbound_Staging__c(
            Raw_Advertiser_Name__c  = 'Controller Test Advertiser',
            Raw_Salesperson_Code__c = 'AE200',
            Revenue_Amount__c       = 7500,
            Revenue_Type__c         = 'Digital',
            Period_Month__c         = 4,
            Period_Year__c          = 2026,
            External_Key__c         = 'EXT-CTRL-001',
            Status__c               = 'Unmatched',
            AE_User__c              = aeUser.Id,
            Match_Account_Tier__c   = 3,
            Source_System__c        = ss.Id
        );
        insert stg;
    }

    // ── getAeWorklist ─────────────────────────────────────────────────────────

    @IsTest
    static void testGetAeWorklist() {
        User aeUser = [SELECT Id FROM User WHERE AE_Code__c = 'AE200' LIMIT 1];

        Test.startTest();
        ReconciliationController.WorklistResult result =
            ReconciliationController.getAeWorklist(aeUser.Id, 50, 0);
        Test.stopTest();

        Assert.isFalse(result.rows.isEmpty(), 'Expected unmatched rows for AE');
        Assert.areEqual(1, result.totalCount);
        ReconciliationController.WorklistRow row = result.rows[0];
        Assert.areEqual('Controller Test Advertiser', row.rawAdvertiserName);
        Assert.areEqual(7500, row.revenueAmount);
    }

    // ── getSalesOpsWorklist ───────────────────────────────────────────────────

    @IsTest
    static void testGetSalesOpsWorklist_noFilter() {
        Test.startTest();
        ReconciliationController.WorklistResult result =
            ReconciliationController.getSalesOpsWorklist(null, null, null, null, 100, 0);
        Test.stopTest();

        Assert.isTrue(result.totalCount >= 1, 'Sales Ops worklist should include all unmatched rows');
    }

    @IsTest
    static void testGetSalesOpsWorklist_aeFilter() {
        User aeUser = [SELECT Id FROM User WHERE AE_Code__c = 'AE200' LIMIT 1];

        Test.startTest();
        ReconciliationController.WorklistResult result =
            ReconciliationController.getSalesOpsWorklist(aeUser.Id, null, null, null, 100, 0);
        Test.stopTest();

        Assert.areEqual(1, result.totalCount);
    }

    // ── acceptMatch ───────────────────────────────────────────────────────────

    @IsTest
    static void testAcceptMatch() {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Controller Test Advertiser' LIMIT 1];
        Inbound_Staging__c stg = [SELECT Id FROM Inbound_Staging__c WHERE External_Key__c = 'EXT-CTRL-001'];

        Test.startTest();
        String outcome = ReconciliationController.acceptMatch(stg.Id, adv.Id, 2);
        Test.stopTest();

        Assert.areEqual('success', outcome);

        stg = [SELECT Status__c, Account__c FROM Inbound_Staging__c WHERE Id = :stg.Id];
        Assert.areEqual('Matched', stg.Status__c);
        Assert.areEqual(adv.Id, stg.Account__c);

        Assert.areEqual(1, [SELECT COUNT() FROM Actual_Revenue__c WHERE External_Key__c = 'EXT-CTRL-001']);
    }

    // ── excludeRow ────────────────────────────────────────────────────────────

    @IsTest
    static void testExcludeRow() {
        Inbound_Staging__c stg = [SELECT Id FROM Inbound_Staging__c WHERE External_Key__c = 'EXT-CTRL-001'];

        Test.startTest();
        String outcome = ReconciliationController.excludeRow(stg.Id, 'TEST_EXCLUDE');
        Test.stopTest();

        Assert.areEqual('success', outcome);
        stg = [SELECT Status__c, Excluding_Rule__c FROM Inbound_Staging__c WHERE Id = :stg.Id];
        Assert.areEqual('Excluded', stg.Status__c);
        Assert.areEqual('TEST_EXCLUDE', stg.Excluding_Rule__c);
    }

    // ── searchAccounts ────────────────────────────────────────────────────────

    @IsTest
    static void testSearchAccounts_returnsResults() {
        Test.startTest();
        List<AccountMatcher.MatchSuggestion> results =
            ReconciliationController.searchAccounts('Controller Test');
        Test.stopTest();

        Assert.isFalse(results.isEmpty());
        Assert.areEqual('MANUAL_SEARCH', results[0].method);
    }

    @IsTest
    static void testSearchAccounts_shortTerm() {
        List<AccountMatcher.MatchSuggestion> results =
            ReconciliationController.searchAccounts('X');
        Assert.isTrue(results.isEmpty());
    }

    // ── acceptMatch — not found ───────────────────────────────────────────────

    @IsTest
    static void testAcceptMatch_notFound() {
        Test.startTest();
        String outcome = ReconciliationController.acceptMatch(
            UserInfo.getUserId(), // bogus staging Id
            UserInfo.getUserId(),
            1
        );
        Test.stopTest();

        Assert.isTrue(outcome.startsWith('Error'));
    }
}
