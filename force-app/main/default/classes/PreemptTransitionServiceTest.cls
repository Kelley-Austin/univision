@IsTest
private class PreemptTransitionServiceTest {

    @TestSetup
    static void setupData() {
        Id advRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();
        Account adv = new Account(Name = 'Preempt Test Advertiser', RecordTypeId = advRtId);
        insert adv;

        Category__c cat = new Category__c(Name = 'Preempt Test Category');
        insert cat;
    }

    private static Actual_Revenue__c makePreempt(String externalKey, String orderNum,
                                                 Decimal amount, String calType,
                                                 Decimal year, Decimal month,
                                                 String preemptStatus) {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Preempt Test Advertiser' LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c WHERE Name = 'Preempt Test Category' LIMIT 1];
        return new Actual_Revenue__c(
            External_Key__c        = externalKey,
            Account__c             = adv.Id,
            Category__c            = cat.Id,
            Revenue_Type__c        = 'National TV',
            Period_Year__c         = year,
            Period_Month__c        = month,
            Revenue_Amount__c      = amount,
            Calendar_Type__c       = calType,
            Is_Preempt__c          = true,
            Preempt_Status__c      = preemptStatus,
            Source_Order_Number__c = orderNum
        );
    }

    private static Actual_Revenue__c makeBooked(String externalKey, String orderNum,
                                                Decimal amount, String calType,
                                                Decimal year, Decimal month) {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Preempt Test Advertiser' LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c WHERE Name = 'Preempt Test Category' LIMIT 1];
        return new Actual_Revenue__c(
            External_Key__c        = externalKey,
            Account__c             = adv.Id,
            Category__c            = cat.Id,
            Revenue_Type__c        = 'National TV',
            Period_Year__c         = year,
            Period_Month__c        = month,
            Revenue_Amount__c      = amount,
            Calendar_Type__c       = calType,
            Is_Preempt__c          = false,
            Source_Order_Number__c = orderNum
        );
    }

    // ── Happy path: booked actual supersedes single active preempt ────────────

    @IsTest
    static void testSupersede_singlePreempt() {
        Actual_Revenue__c preempt = makePreempt('PRE-001', 'ORD-100', 1000, 'Calendar', 2026, 3, 'Active');
        insert preempt;

        Actual_Revenue__c booked = makeBooked('BOOK-001', 'ORD-100', 1200, 'Calendar', 2026, 3);
        insert booked;

        Test.startTest();
        PreemptTransitionService.process(new Set<Id>{ booked.Id });
        Test.stopTest();

        Actual_Revenue__c reloaded = [SELECT Preempt_Status__c FROM Actual_Revenue__c WHERE Id = :preempt.Id];
        Assert.areEqual('Superseded', reloaded.Preempt_Status__c);

        List<Preempt_Transition_Log__c> logs = [
            SELECT Original_Preempt__c, Booked_Actual__c, Transition_Type__c,
                   Reversed_Amount__c, Applied_Amount__c, Net_Adjustment__c,
                   Source_Order_Number__c, Calendar_Type__c
            FROM Preempt_Transition_Log__c
        ];
        Assert.areEqual(1, logs.size());
        Assert.areEqual('Supersede', logs[0].Transition_Type__c);
        Assert.areEqual(preempt.Id, logs[0].Original_Preempt__c);
        Assert.areEqual(booked.Id, logs[0].Booked_Actual__c);
        Assert.areEqual(1000, logs[0].Reversed_Amount__c);
        Assert.areEqual(1200, logs[0].Applied_Amount__c);
        Assert.areEqual(200, logs[0].Net_Adjustment__c);
        Assert.areEqual('ORD-100', logs[0].Source_Order_Number__c);
    }

    // ── Cancellation row supersedes prior preempt with no booked applied ──────

    @IsTest
    static void testCancellation() {
        Actual_Revenue__c preempt = makePreempt('PRE-002', 'ORD-200', 800, 'Broadcast', 2026, 4, 'Active');
        insert preempt;

        Actual_Revenue__c cancellation = makePreempt('CXL-002', 'ORD-200', 800, 'Broadcast', 2026, 4, 'Cancelled');
        insert cancellation;

        Test.startTest();
        PreemptTransitionService.process(new Set<Id>{ cancellation.Id });
        Test.stopTest();

        Actual_Revenue__c reloaded = [SELECT Preempt_Status__c FROM Actual_Revenue__c WHERE Id = :preempt.Id];
        Assert.areEqual('Superseded', reloaded.Preempt_Status__c);

        Preempt_Transition_Log__c log = [
            SELECT Transition_Type__c, Reversed_Amount__c, Applied_Amount__c,
                   Net_Adjustment__c, Booked_Actual__c
            FROM Preempt_Transition_Log__c
            LIMIT 1
        ];
        Assert.areEqual('Cancellation', log.Transition_Type__c);
        Assert.areEqual(800, log.Reversed_Amount__c);
        Assert.areEqual(0, log.Applied_Amount__c);
        Assert.areEqual(-800, log.Net_Adjustment__c);
        Assert.isNull(log.Booked_Actual__c);
    }

    // ── No prior preempt: booked is upserted but service no-ops ───────────────

    @IsTest
    static void testBooked_noPriorPreempt() {
        Actual_Revenue__c booked = makeBooked('BOOK-NP', 'ORD-NP', 500, 'Calendar', 2026, 5);
        insert booked;

        Test.startTest();
        PreemptTransitionService.process(new Set<Id>{ booked.Id });
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Preempt_Transition_Log__c]);
    }

    // ── Booked without Source_Order_Number is ignored ─────────────────────────

    @IsTest
    static void testBooked_noOrderNumber_ignored() {
        Actual_Revenue__c preempt = makePreempt('PRE-NO', 'ORD-NO', 100, 'Calendar', 2026, 6, 'Active');
        insert preempt;

        Actual_Revenue__c booked = makeBooked('BOOK-NO', null, 200, 'Calendar', 2026, 6);
        insert booked;

        Test.startTest();
        PreemptTransitionService.process(new Set<Id>{ booked.Id });
        Test.stopTest();

        Actual_Revenue__c reloaded = [SELECT Preempt_Status__c FROM Actual_Revenue__c WHERE Id = :preempt.Id];
        Assert.areEqual('Active', reloaded.Preempt_Status__c, 'Preempt should remain Active when booked has no order number');
        Assert.areEqual(0, [SELECT COUNT() FROM Preempt_Transition_Log__c]);
    }

    // ── Period mismatch: not superseded ───────────────────────────────────────

    @IsTest
    static void testNoMatch_periodMismatch() {
        Actual_Revenue__c preempt = makePreempt('PRE-PM', 'ORD-PM', 100, 'Calendar', 2026, 7, 'Active');
        insert preempt;

        Actual_Revenue__c booked = makeBooked('BOOK-PM', 'ORD-PM', 100, 'Calendar', 2026, 8);
        insert booked;

        Test.startTest();
        PreemptTransitionService.process(new Set<Id>{ booked.Id });
        Test.stopTest();

        Actual_Revenue__c reloaded = [SELECT Preempt_Status__c FROM Actual_Revenue__c WHERE Id = :preempt.Id];
        Assert.areEqual('Active', reloaded.Preempt_Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Preempt_Transition_Log__c]);
    }

    // ── Calendar type mismatch: not superseded ────────────────────────────────

    @IsTest
    static void testNoMatch_calendarMismatch() {
        Actual_Revenue__c preempt = makePreempt('PRE-CM', 'ORD-CM', 100, 'Calendar', 2026, 9, 'Active');
        insert preempt;

        Actual_Revenue__c booked = makeBooked('BOOK-CM', 'ORD-CM', 100, 'Broadcast', 2026, 9);
        insert booked;

        Test.startTest();
        PreemptTransitionService.process(new Set<Id>{ booked.Id });
        Test.stopTest();

        Actual_Revenue__c reloaded = [SELECT Preempt_Status__c FROM Actual_Revenue__c WHERE Id = :preempt.Id];
        Assert.areEqual('Active', reloaded.Preempt_Status__c);
    }

    // ── Multiple preempts on same key all marked Superseded ───────────────────

    @IsTest
    static void testSupersede_multiplePreempts() {
        Actual_Revenue__c p1 = makePreempt('PRE-M1', 'ORD-M', 300, 'Calendar', 2026, 10, 'Active');
        Actual_Revenue__c p2 = makePreempt('PRE-M2', 'ORD-M', 400, 'Calendar', 2026, 10, 'Active');
        insert new List<Actual_Revenue__c>{ p1, p2 };

        Actual_Revenue__c booked = makeBooked('BOOK-M', 'ORD-M', 800, 'Calendar', 2026, 10);
        insert booked;

        Test.startTest();
        PreemptTransitionService.process(new Set<Id>{ booked.Id });
        Test.stopTest();

        List<Actual_Revenue__c> reloaded = [
            SELECT Id, Preempt_Status__c FROM Actual_Revenue__c
            WHERE Id IN (:p1.Id, :p2.Id) ORDER BY External_Key__c
        ];
        Assert.areEqual('Superseded', reloaded[0].Preempt_Status__c);
        Assert.areEqual('Superseded', reloaded[1].Preempt_Status__c);
        Assert.areEqual(2, [SELECT COUNT() FROM Preempt_Transition_Log__c]);
    }

    // ── Already-superseded preempts are not re-marked ─────────────────────────

    @IsTest
    static void testIdempotent_alreadySuperseded() {
        Actual_Revenue__c preempt = makePreempt('PRE-ID', 'ORD-ID', 250, 'Calendar', 2026, 11, 'Superseded');
        insert preempt;

        Actual_Revenue__c booked = makeBooked('BOOK-ID', 'ORD-ID', 250, 'Calendar', 2026, 11);
        insert booked;

        Test.startTest();
        PreemptTransitionService.process(new Set<Id>{ booked.Id });
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Preempt_Transition_Log__c],
            'Already-Superseded preempt should not generate a new transition log');
    }

    // ── Empty input is a safe no-op ───────────────────────────────────────────

    @IsTest
    static void testProcess_emptyInput() {
        PreemptTransitionService.process(null);
        PreemptTransitionService.process(new Set<Id>());
        Assert.areEqual(0, [SELECT COUNT() FROM Preempt_Transition_Log__c]);
    }

    // ── Bulk: 100 preempts → 100 booked → 100 log rows in single batch ────────

    @IsTest
    static void testProcess_bulk() {
        Account adv = [SELECT Id FROM Account WHERE Name = 'Preempt Test Advertiser' LIMIT 1];
        Category__c cat = [SELECT Id FROM Category__c WHERE Name = 'Preempt Test Category' LIMIT 1];

        List<Actual_Revenue__c> preempts = new List<Actual_Revenue__c>();
        for (Integer i = 0; i < 100; i++) {
            preempts.add(new Actual_Revenue__c(
                External_Key__c        = 'PRE-BULK-' + i,
                Account__c             = adv.Id,
                Category__c            = cat.Id,
                Revenue_Type__c        = 'National TV',
                Period_Year__c         = 2026,
                Period_Month__c        = 12,
                Revenue_Amount__c      = 100,
                Calendar_Type__c       = 'Calendar',
                Is_Preempt__c          = true,
                Preempt_Status__c      = 'Active',
                Source_Order_Number__c = 'ORD-BULK-' + i
            ));
        }
        insert preempts;

        List<Actual_Revenue__c> booked = new List<Actual_Revenue__c>();
        for (Integer i = 0; i < 100; i++) {
            booked.add(new Actual_Revenue__c(
                External_Key__c        = 'BOOK-BULK-' + i,
                Account__c             = adv.Id,
                Category__c            = cat.Id,
                Revenue_Type__c        = 'National TV',
                Period_Year__c         = 2026,
                Period_Month__c        = 12,
                Revenue_Amount__c      = 110,
                Calendar_Type__c       = 'Calendar',
                Is_Preempt__c          = false,
                Source_Order_Number__c = 'ORD-BULK-' + i
            ));
        }
        insert booked;

        Set<Id> bookedIds = new Set<Id>();
        for (Actual_Revenue__c b : booked) bookedIds.add(b.Id);

        Test.startTest();
        PreemptTransitionService.process(bookedIds);
        Test.stopTest();

        Assert.areEqual(100, [SELECT COUNT() FROM Preempt_Transition_Log__c]);
        Assert.areEqual(100, [
            SELECT COUNT() FROM Actual_Revenue__c
            WHERE Preempt_Status__c = 'Superseded' AND External_Key__c LIKE 'PRE-BULK-%'
        ]);
    }
}
