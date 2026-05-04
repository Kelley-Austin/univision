@IsTest
private class AccountMatcherTest {

    // ── Test data setup ───────────────────────────────────────────────────────

    @TestSetup
    static void setupData() {
        Id rtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();

        Account a1 = new Account(
            Name = 'Acme Corporation',
            MDM_External_Id__c = 'MDM-001',
            RecordTypeId = rtId
        );
        Account a2 = new Account(
            Name = 'Global Media Inc',
            MDM_External_Id__c = 'MDM-002',
            RecordTypeId = rtId
        );
        Account a3 = new Account(
            Name = 'Pacific Advertising LLC',
            RecordTypeId = rtId
        );
        insert new List<Account>{ a1, a2, a3 };
    }

    // ── normalizeName ─────────────────────────────────────────────────────────

    @IsTest
    static void testNormalizeName() {
        Assert.areEqual('acme corporation', AccountMatcher.normalizeName('Acme Corporation'));
        Assert.areEqual('acme', AccountMatcher.normalizeName('Acme, Inc.'));
        Assert.areEqual('global media', AccountMatcher.normalizeName('Global Media LLC'));
        Assert.areEqual('', AccountMatcher.normalizeName(null));
        Assert.areEqual('', AccountMatcher.normalizeName('   '));
    }

    // ── similarityScore ───────────────────────────────────────────────────────

    @IsTest
    static void testSimilarityScore_identical() {
        Assert.areEqual(100, AccountMatcher.similarityScore('acme', 'acme'));
    }

    @IsTest
    static void testSimilarityScore_oneOff() {
        Integer score = AccountMatcher.similarityScore('acme corp', 'acme corp.');
        Assert.isTrue(score > 85, 'Expected high score for minor diff, got ' + score);
    }

    @IsTest
    static void testSimilarityScore_unrelated() {
        Integer score = AccountMatcher.similarityScore('xyz', 'abcdefg');
        Assert.isTrue(score < 50, 'Expected low score for unrelated, got ' + score);
    }

    @IsTest
    static void testSimilarityScore_blanks() {
        Assert.areEqual(100, AccountMatcher.similarityScore('', ''));
        Assert.areEqual(0,   AccountMatcher.similarityScore('',  'abc'));
        Assert.areEqual(0,   AccountMatcher.similarityScore('abc', ''));
    }

    // ── tier1Lookup ───────────────────────────────────────────────────────────

    @IsTest
    static void testTier1Lookup_hit() {
        Test.startTest();
        Map<String, Id> result = AccountMatcher.tier1Lookup(new Set<String>{ 'MDM-001' });
        Test.stopTest();
        Assert.isFalse(result.isEmpty(), 'Expected a hit for MDM-001');
        Assert.isTrue(result.containsKey('mdm-001'));
    }

    @IsTest
    static void testTier1Lookup_miss() {
        Test.startTest();
        Map<String, Id> result = AccountMatcher.tier1Lookup(new Set<String>{ 'UNKNOWN-999' });
        Test.stopTest();
        Assert.isTrue(result.isEmpty());
    }

    @IsTest
    static void testTier1Lookup_empty() {
        Map<String, Id> result = AccountMatcher.tier1Lookup(new Set<String>());
        Assert.isTrue(result.isEmpty());
    }

    // ── matchBulk — Tier 1 path ───────────────────────────────────────────────

    @IsTest
    static void testMatchBulk_tier1() {
        Id ssId = [SELECT Id FROM Source_System__c LIMIT 1]?.Id;
        Inbound_Staging__c row = new Inbound_Staging__c(
            Raw_Advertiser_Code__c = 'MDM-001',
            Raw_Advertiser_Name__c = 'Something Completely Different',
            Status__c = 'Pending'
        );

        Test.startTest();
        List<AccountMatcher.MatchResult> results = AccountMatcher.matchBulk(
            new List<Inbound_Staging__c>{ row }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        AccountMatcher.MatchResult r = results[0];
        Assert.areEqual(1, r.tier);
        Assert.areEqual('MDM_EXACT', r.method);
        Assert.isNotNull(r.accountId);
    }

    // ── matchBulk — Tier 3 manual queue ──────────────────────────────────────

    @IsTest
    static void testMatchBulk_tier3_noMatch() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Raw_Advertiser_Name__c = 'Zzz Completely Unknwon Advertizer Xyz',
            Status__c = 'Pending'
        );

        Test.startTest();
        List<AccountMatcher.MatchResult> results = AccountMatcher.matchBulk(
            new List<Inbound_Staging__c>{ row }
        );
        Test.stopTest();

        AccountMatcher.MatchResult r = results[0];
        Assert.areEqual(3, r.tier);
        Assert.areEqual('MANUAL_QUEUE', r.method);
        Assert.isNull(r.accountId);
    }
}
