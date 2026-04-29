@IsTest
private class ActualRevenueTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        Id advRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();
        Account adv = new Account(Name = 'Trigger Test Advertiser', RecordTypeId = advRtId);
        insert adv;

        Category__c cat = new Category__c(Name = 'Digital Spot');
        insert cat;

        // A closed period: Jan 2026 closed on Jan 31
        Period_Close__c pc = new Period_Close__c(
            Period_Month__c = 1,
            Period_Year__c  = 2026,
            Close_Date__c   = Date.newInstance(2026, 1, 31),
            Status__c       = 'Closed',
            Composite_Key__c = '2026|1'
        );
        insert pc;
    }

    // ── Category_Snapshot populated on insert ─────────────────────────────────

    @IsTest
    static void testCategorySnapshot_populatedOnInsert() {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Trigger Test Advertiser' LIMIT 1];
        Category__c cat = [SELECT Id, Name FROM Category__c WHERE Name = 'Digital Spot' LIMIT 1];

        Actual_Revenue__c a = new Actual_Revenue__c(
            Account__c       = adv.Id,
            Category__c      = cat.Id,
            Revenue_Type__c  = 'Digital',
            Period_Month__c  = 3,
            Period_Year__c   = 2026,
            Revenue_Amount__c = 1000,
            External_Key__c  = 'EXT-TRIGGER-001'
        );

        Test.startTest();
        insert a;
        Test.stopTest();

        a = [SELECT Category_Snapshot__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.areEqual('Digital Spot', a.Category_Snapshot__c);
    }

    // ── Category_Snapshot is immutable on update ──────────────────────────────

    @IsTest
    static void testCategorySnapshot_immutableOnUpdate() {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Trigger Test Advertiser' LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c WHERE Name = 'Digital Spot' LIMIT 1];

        Actual_Revenue__c a = new Actual_Revenue__c(
            Account__c        = adv.Id,
            Category__c       = cat.Id,
            Revenue_Type__c   = 'Digital',
            Period_Month__c   = 3,
            Period_Year__c    = 2026,
            Revenue_Amount__c = 500,
            External_Key__c   = 'EXT-TRIGGER-002'
        );
        insert a;

        // Attempt to overwrite snapshot
        a.Category_Snapshot__c = 'Tampered Value';
        Test.startTest();
        update a;
        Test.stopTest();

        a = [SELECT Category_Snapshot__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.areEqual('Digital Spot', a.Category_Snapshot__c, 'Snapshot must not change on update');
    }

    // ── Is_Late__c flagged for closed period ──────────────────────────────────

    @IsTest
    static void testIsLate_closedPeriod() {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Trigger Test Advertiser' LIMIT 1];

        Actual_Revenue__c a = new Actual_Revenue__c(
            Account__c        = adv.Id,
            Revenue_Type__c   = 'National TV',
            Period_Month__c   = 1,   // Jan 2026 is closed
            Period_Year__c    = 2026,
            Revenue_Amount__c = 2000,
            External_Key__c   = 'EXT-TRIGGER-003'
        );

        Test.startTest();
        insert a;
        Test.stopTest();

        a = [SELECT Is_Late__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        // Today (2026-04-29) is after Jan 31, 2026 close date → Is_Late = true
        Assert.isTrue(a.Is_Late__c, 'Record inserted after closed period should be Is_Late = true');
    }

    // ── Is_Late__c false for open period ─────────────────────────────────────

    @IsTest
    static void testIsLate_openPeriod() {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Trigger Test Advertiser' LIMIT 1];

        Actual_Revenue__c a = new Actual_Revenue__c(
            Account__c        = adv.Id,
            Revenue_Type__c   = 'Radio',
            Period_Month__c   = 6,   // No Period_Close record → not late
            Period_Year__c    = 2026,
            Revenue_Amount__c = 750,
            External_Key__c   = 'EXT-TRIGGER-004'
        );

        Test.startTest();
        insert a;
        Test.stopTest();

        a = [SELECT Is_Late__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.isFalse(a.Is_Late__c, 'Record with no period close should not be late');
    }

    // ── No category: snapshot stays blank ────────────────────────────────────

    @IsTest
    static void testCategorySnapshot_noCategoryBlank() {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Trigger Test Advertiser' LIMIT 1];

        Actual_Revenue__c a = new Actual_Revenue__c(
            Account__c        = adv.Id,
            Revenue_Type__c   = 'Streaming',
            Period_Month__c   = 4,
            Period_Year__c    = 2026,
            Revenue_Amount__c = 300,
            External_Key__c   = 'EXT-TRIGGER-005'
        );
        insert a;

        a = [SELECT Category_Snapshot__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.isTrue(String.isBlank(a.Category_Snapshot__c));
    }
}
