@IsTest
private class SalespersonMatcherTest {

    @TestSetup
    static void setupData() {
        // Create a test User with AE_Code__c and Alias
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User aeUser = new User(
            FirstName   = 'Test',
            LastName    = 'AE',
            Email       = 'testae@example.com',
            Username    = 'testae_reconcile@example.com.unittest',
            Alias       = 'TSTAEV',
            AE_Code__c  = 'AE001',
            ProfileId   = p.Id,
            TimeZoneSidKey    = 'America/Chicago',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert aeUser;
    }

    // ── normalizeCode ─────────────────────────────────────────────────────────

    @IsTest
    static void testNormalizeCode() {
        Assert.areEqual('ae1',   SalespersonMatcher.normalizeCode('AE001'));
        Assert.areEqual('ae001', SalespersonMatcher.normalizeCode(' AE001 '));
        Assert.areEqual('',      SalespersonMatcher.normalizeCode(null));
        Assert.areEqual('',      SalespersonMatcher.normalizeCode(''));
        Assert.areEqual('abc',   SalespersonMatcher.normalizeCode('ABC'));
    }

    // ── Tier 1: exact AE_Code__c ──────────────────────────────────────────────

    @IsTest
    static void testMatchBulk_tier1_exact() {
        Test.startTest();
        Map<String, SalespersonMatcher.AEMatchResult> results =
            SalespersonMatcher.matchBulk(new Set<String>{ 'AE001' }, 'WO');
        Test.stopTest();

        Assert.isTrue(results.containsKey('AE001'));
        SalespersonMatcher.AEMatchResult r = results.get('AE001');
        Assert.areEqual(1, r.tier);
        Assert.areEqual('AE_CODE_EXACT', r.method);
        Assert.isNotNull(r.userId);
    }

    // ── Tier 3: normalized code ───────────────────────────────────────────────

    @IsTest
    static void testMatchBulk_tier3_normalized() {
        // 'AE-001' normalizes to 'ae1' which should match AE_Code__c 'AE001' normalized
        // Wait — normalizeCode('AE001') = 'ae1' and normalizeCode('AE-001') = 'ae1', so they match
        Test.startTest();
        Map<String, SalespersonMatcher.AEMatchResult> results =
            SalespersonMatcher.matchBulk(new Set<String>{ 'AE-001' }, 'WO');
        Test.stopTest();

        Assert.isTrue(results.containsKey('AE-001'));
        SalespersonMatcher.AEMatchResult r = results.get('AE-001');
        // Will be Tier 1 miss, Tier 2 miss (no alias yet), Tier 3 normalized match
        Assert.isTrue(r.tier <= 3, 'Expected Tier 1-3, got ' + r.tier);
        Assert.isNotNull(r.userId);
    }

    // ── Tier 4: User.Alias ────────────────────────────────────────────────────

    @IsTest
    static void testMatchBulk_tier4_userAlias() {
        // 'TSTAEV' is the User.Alias set in setup
        Test.startTest();
        Map<String, SalespersonMatcher.AEMatchResult> results =
            SalespersonMatcher.matchBulk(new Set<String>{ 'TSTAEV' }, 'WO');
        Test.stopTest();

        Assert.isTrue(results.containsKey('TSTAEV'));
        SalespersonMatcher.AEMatchResult r = results.get('TSTAEV');
        Assert.isTrue(r.tier <= 4, 'Expected Tier 1-4, got ' + r.tier);
        Assert.isNotNull(r.userId);
    }

    // ── Tier 5: unmatched ─────────────────────────────────────────────────────

    @IsTest
    static void testMatchBulk_tier5_unmatched() {
        Test.startTest();
        Map<String, SalespersonMatcher.AEMatchResult> results =
            SalespersonMatcher.matchBulk(new Set<String>{ 'ZZZZUNKNOWN99' }, 'WO');
        Test.stopTest();

        SalespersonMatcher.AEMatchResult r = results.get('ZZZZUNKNOWN99');
        Assert.areEqual(5, r.tier);
        Assert.areEqual('UNMATCHED', r.method);
        Assert.isNull(r.userId);
    }

    // ── Self-healing alias write ──────────────────────────────────────────────

    @IsTest
    static void testSelfHealingAlias_tier3() {
        Integer before = [SELECT COUNT() FROM AE_Code_Alias__c];

        Test.startTest();
        // Force a Tier 3 match: 'AE-001' normalizes same as 'AE001'
        SalespersonMatcher.matchBulk(new Set<String>{ 'AE-001' }, 'WO');
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM AE_Code_Alias__c];
        Assert.isTrue(after > before, 'Expected a self-heal alias to be written');
    }

    // ── Alias table (Tier 2) after self-heal ──────────────────────────────────

    @IsTest
    static void testMatchBulk_tier2_aliasTable() {
        User u = [SELECT Id FROM User WHERE AE_Code__c = 'AE001' LIMIT 1];

        // Pre-seed an alias
        AE_Code_Alias__c alias = new AE_Code_Alias__c(
            Name    = 'AE-ALIAS',
            User__c = u.Id,
            Match_Tier__c = 3
        );
        insert alias;

        Test.startTest();
        Map<String, SalespersonMatcher.AEMatchResult> results =
            SalespersonMatcher.matchBulk(new Set<String>{ 'AE-ALIAS' }, 'WO');
        Test.stopTest();

        SalespersonMatcher.AEMatchResult r = results.get('AE-ALIAS');
        Assert.areEqual(2, r.tier);
        Assert.areEqual('ALIAS_TABLE', r.method);
        Assert.areEqual(u.Id, r.userId);
    }

    // ── Empty input ───────────────────────────────────────────────────────────

    @IsTest
    static void testMatchBulk_empty() {
        Map<String, SalespersonMatcher.AEMatchResult> results =
            SalespersonMatcher.matchBulk(new Set<String>(), 'WO');
        Assert.isTrue(results.isEmpty());
    }
}
