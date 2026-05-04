@IsTest
private class ReconciliationEngineTest {

    @TestSetup
    static void setupData() {
        Id advRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();
        Account adv = new Account(
            Name             = 'WideOrbit Test Advertiser',
            MDM_External_Id__c = 'WO-ADV-001',
            RecordTypeId     = advRtId
        );
        insert adv;

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User aeUser = new User(
            FirstName   = 'AE',
            LastName    = 'Recon',
            Email       = 'ae.recon@example.com',
            Username    = 'ae.recon@example.com.unittest',
            Alias       = 'AERCN',
            AE_Code__c  = 'AE100',
            ProfileId   = p.Id,
            TimeZoneSidKey    = 'America/Chicago',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert aeUser;

        Source_System__c ss = new Source_System__c(
            Name      = 'WideOrbit',
            Code__c   = 'WIDEORBIT'
        );
        insert ss;

        // Create a Pending staging row for the advertiser (Tier 1 match via MDM code)
        Inbound_Staging__c stg = new Inbound_Staging__c(
            Raw_Advertiser_Name__c  = 'WideOrbit Test Advertiser',
            Raw_Advertiser_Code__c  = 'WO-ADV-001',
            Raw_Salesperson_Code__c = 'AE100',
            Revenue_Amount__c       = 5000,
            Revenue_Type__c         = 'National TV',
            Period_Month__c         = 3,
            Period_Year__c          = 2026,
            Station_Code__c         = 'KVEA',
            External_Key__c         = 'EXT-RECON-001',
            Status__c               = 'Pending',
            Source_System__c        = ss.Id
        );
        insert stg;
    }

    // ── Full end-to-end reconcile ─────────────────────────────────────────────

    @IsTest
    static void testReconcileBatch_endToEnd() {
        List<Inbound_Staging__c> rows = [
            SELECT Id, Status__c, External_Key__c,
                   Raw_Advertiser_Name__c, Raw_Advertiser_Code__c,
                   Raw_Salesperson_Code__c, Advertiser_Name__c,
                   Revenue_Amount__c, Revenue_Type__c,
                   Period_Month__c, Period_Year__c,
                   Station_Code__c, Outlet_Code__c, Broadcast_Period__c,
                   Source_System__c, Load_Batch__c,
                   Account__c, AE_User__c,
                   Match_Account_Tier__c, Match_AE_Tier__c,
                   Excluding_Rule__c
            FROM Inbound_Staging__c
            WHERE Status__c = 'Pending'
        ];
        Assert.isFalse(rows.isEmpty(), 'Test setup should have created a Pending row');

        Test.startTest();
        ReconciliationEngine.ReconcileResult result =
            ReconciliationEngine.reconcileBatch(rows, 'WIDEORBIT');
        Test.stopTest();

        // Expect 1 matched (Tier 1 account match via MDM code)
        Assert.areEqual(1, result.matched, 'Expected 1 matched row');
        Assert.areEqual(0, result.unmatched);

        // Actual_Revenue__c should have been upserted
        List<Actual_Revenue__c> actuals = [
            SELECT Id, External_Key__c, Revenue_Amount__c, Account__c,
                   Period_Month__c, Period_Year__c
            FROM Actual_Revenue__c
            WHERE External_Key__c = 'EXT-RECON-001'
        ];
        Assert.areEqual(1, actuals.size(), 'Expected one Actual_Revenue__c record');
        Assert.areEqual(5000, actuals[0].Revenue_Amount__c);
        Assert.areEqual(3, actuals[0].Period_Month__c.intValue());

        // Staging row should be Matched with tier stamped
        Inbound_Staging__c updated = [
            SELECT Status__c, Match_Account_Tier__c, Match_AE_Tier__c, Account__c
            FROM Inbound_Staging__c
            WHERE External_Key__c = 'EXT-RECON-001'
        ];
        Assert.areEqual('Matched', updated.Status__c);
        Assert.areEqual(1, updated.Match_Account_Tier__c.intValue());
        Assert.isNotNull(updated.Account__c);
    }

    // ── Unmatched row surfaces correctly ──────────────────────────────────────

    @IsTest
    static void testReconcileBatch_unmatchedRow() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Raw_Advertiser_Name__c  = 'Zzz Completely Unknown Advertiser XYZQQ',
            Raw_Salesperson_Code__c = 'UNKNOWN_AE',
            Revenue_Amount__c       = 1000,
            Revenue_Type__c         = 'Digital',
            Period_Month__c         = 1,
            Period_Year__c          = 2026,
            External_Key__c         = 'EXT-UNMATCHED-001',
            Status__c               = 'Pending'
        );
        insert row;

        List<Inbound_Staging__c> rows = [
            SELECT Id, Status__c, External_Key__c,
                   Raw_Advertiser_Name__c, Raw_Advertiser_Code__c,
                   Raw_Salesperson_Code__c, Advertiser_Name__c,
                   Revenue_Amount__c, Revenue_Type__c,
                   Period_Month__c, Period_Year__c,
                   Station_Code__c, Outlet_Code__c, Broadcast_Period__c,
                   Source_System__c, Load_Batch__c,
                   Account__c, AE_User__c,
                   Match_Account_Tier__c, Match_AE_Tier__c,
                   Excluding_Rule__c
            FROM Inbound_Staging__c
            WHERE External_Key__c = 'EXT-UNMATCHED-001'
        ];

        Test.startTest();
        ReconciliationEngine.ReconcileResult result =
            ReconciliationEngine.reconcileBatch(rows, 'WIDEORBIT');
        Test.stopTest();

        Assert.areEqual(0, result.matched);
        Assert.areEqual(1, result.unmatched);

        Inbound_Staging__c updated = [
            SELECT Status__c, Match_Account_Tier__c
            FROM Inbound_Staging__c
            WHERE External_Key__c = 'EXT-UNMATCHED-001'
        ];
        Assert.areEqual('Unmatched', updated.Status__c);
        Assert.areEqual(3, updated.Match_Account_Tier__c.intValue());
    }

    // ── Empty input ───────────────────────────────────────────────────────────

    @IsTest
    static void testReconcileBatch_emptyList() {
        ReconciliationEngine.ReconcileResult result =
            ReconciliationEngine.reconcileBatch(new List<Inbound_Staging__c>(), 'WIDEORBIT');
        Assert.areEqual(0, result.matched);
        Assert.areEqual(0, result.unmatched);
    }

    // ── Idempotency: re-reconciling same rows doesn't duplicate actuals ────────

    @IsTest
    static void testReconcileBatch_idempotent() {
        List<Inbound_Staging__c> rows = [
            SELECT Id, Status__c, External_Key__c,
                   Raw_Advertiser_Name__c, Raw_Advertiser_Code__c,
                   Raw_Salesperson_Code__c, Advertiser_Name__c,
                   Revenue_Amount__c, Revenue_Type__c,
                   Period_Month__c, Period_Year__c,
                   Station_Code__c, Outlet_Code__c, Broadcast_Period__c,
                   Source_System__c, Load_Batch__c,
                   Account__c, AE_User__c,
                   Match_Account_Tier__c, Match_AE_Tier__c,
                   Excluding_Rule__c
            FROM Inbound_Staging__c
            WHERE External_Key__c = 'EXT-RECON-001'
        ];

        Test.startTest();
        ReconciliationEngine.reconcileBatch(rows, 'WIDEORBIT');
        // Reset status and run again
        for (Inbound_Staging__c r : rows) r.Status__c = 'Pending';
        update rows;
        ReconciliationEngine.reconcileBatch(rows, 'WIDEORBIT');
        Test.stopTest();

        Assert.areEqual(1, [
            SELECT COUNT() FROM Actual_Revenue__c WHERE External_Key__c = 'EXT-RECON-001'
        ]);
    }
}
