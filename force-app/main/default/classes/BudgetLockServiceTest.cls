@IsTest
private class BudgetLockServiceTest {

    static Account makeAccount() {
        Account acct = new Account(Name = 'Test Acct');
        insert acct;
        return acct;
    }

    static Category__c makeCategory() {
        Category__c cat = new Category__c(Name = 'Test Cat', Is_Active__c = true);
        insert cat;
        return cat;
    }

    // ── No locks → not locked ─────────────────────────────────────────────────

    @IsTest
    static void testNoLocks() {
        Account acct = makeAccount();
        Category__c cat = makeCategory();

        Test.startTest();
        BudgetLockService.LockResult result =
            BudgetLockService.checkLock(acct.Id, cat.Id, 'Digital', 2026);
        Test.stopTest();

        System.assertEquals(false, result.isLocked, 'Should not be locked when no locks exist');
    }

    // ── Global lock blocks everything ─────────────────────────────────────────

    @IsTest
    static void testGlobalLock() {
        Account acct = makeAccount();
        Category__c cat = makeCategory();

        insert new Budget_Lock__c(
            Scope_Level__c = 'Global', Period_Year__c = 2026,
            Is_Active__c = true, Lock_Message__c = 'Global freeze.'
        );

        Test.startTest();
        BudgetLockService.LockResult result =
            BudgetLockService.checkLock(acct.Id, cat.Id, 'National TV', 2026);
        Test.stopTest();

        System.assertEquals(true,  result.isLocked,  'Global lock should block all accounts');
        System.assertEquals('Global', result.scopeLevel, 'Scope level should be Global');
        System.assert(result.lockMessage.contains('freeze'), 'Custom message should be returned');
    }

    @IsTest
    static void testGlobalLockDefaultMessage() {
        Account acct = makeAccount();
        Category__c cat = makeCategory();

        insert new Budget_Lock__c(
            Scope_Level__c = 'Global', Period_Year__c = 2026, Is_Active__c = true
        );

        Test.startTest();
        BudgetLockService.LockResult result =
            BudgetLockService.checkLock(acct.Id, cat.Id, 'Digital', 2026);
        Test.stopTest();

        System.assertEquals(true, result.isLocked, 'Global lock should block');
        System.assert(result.lockMessage.contains('Global'), 'Default message should mention scope level');
    }

    // ── Account-scoped lock ───────────────────────────────────────────────────

    @IsTest
    static void testAccountLockBlocksMatchingAccount() {
        Account acct = makeAccount();
        Account other = new Account(Name = 'Other Acct');
        insert other;
        Category__c cat = makeCategory();

        insert new Budget_Lock__c(
            Scope_Level__c = 'Account', Account__c = acct.Id,
            Period_Year__c = 2026, Is_Active__c = true
        );

        Test.startTest();
        BudgetLockService.LockResult locked =
            BudgetLockService.checkLock(acct.Id, cat.Id, 'Digital', 2026);
        BudgetLockService.LockResult notLocked =
            BudgetLockService.checkLock(other.Id, cat.Id, 'Digital', 2026);
        Test.stopTest();

        System.assertEquals(true,  locked.isLocked,    'Locked account should be blocked');
        System.assertEquals(false, notLocked.isLocked, 'Other account should not be blocked');
    }

    // ── Category-scoped lock ──────────────────────────────────────────────────

    @IsTest
    static void testCategoryLock() {
        Account acct = makeAccount();
        Category__c cat = makeCategory();
        Category__c other = new Category__c(Name = 'Other Cat', Is_Active__c = true);
        insert other;

        insert new Budget_Lock__c(
            Scope_Level__c = 'Category', Category__c = cat.Id,
            Period_Year__c = 2026, Is_Active__c = true
        );

        Test.startTest();
        BudgetLockService.LockResult locked =
            BudgetLockService.checkLock(acct.Id, cat.Id, 'Radio', 2026);
        BudgetLockService.LockResult notLocked =
            BudgetLockService.checkLock(acct.Id, other.Id, 'Radio', 2026);
        Test.stopTest();

        System.assertEquals(true,  locked.isLocked,    'Locked category should be blocked');
        System.assertEquals(false, notLocked.isLocked, 'Other category should not be blocked');
    }

    // ── Revenue-type filter ───────────────────────────────────────────────────

    @IsTest
    static void testRevenueTypeFilterOnLock() {
        Account acct = makeAccount();
        Category__c cat = makeCategory();

        insert new Budget_Lock__c(
            Scope_Level__c = 'Global', Revenue_Type__c = 'National TV',
            Period_Year__c = 2026, Is_Active__c = true
        );

        Test.startTest();
        BudgetLockService.LockResult tvLocked =
            BudgetLockService.checkLock(acct.Id, cat.Id, 'National TV', 2026);
        BudgetLockService.LockResult digitalFree =
            BudgetLockService.checkLock(acct.Id, cat.Id, 'Digital', 2026);
        Test.stopTest();

        System.assertEquals(true,  tvLocked.isLocked,   'National TV should be locked');
        System.assertEquals(false, digitalFree.isLocked, 'Digital should not be locked by TV-only lock');
    }

    // ── Inactive lock is ignored ──────────────────────────────────────────────

    @IsTest
    static void testInactiveLockIsIgnored() {
        Account acct = makeAccount();
        Category__c cat = makeCategory();

        insert new Budget_Lock__c(
            Scope_Level__c = 'Global', Period_Year__c = 2026, Is_Active__c = false
        );

        Test.startTest();
        BudgetLockService.LockResult result =
            BudgetLockService.checkLock(acct.Id, cat.Id, 'Streaming', 2026);
        Test.stopTest();

        System.assertEquals(false, result.isLocked, 'Inactive lock should be ignored');
    }

    // ── Wrong year lock is ignored ────────────────────────────────────────────

    @IsTest
    static void testLockForDifferentYearIsIgnored() {
        Account acct = makeAccount();
        Category__c cat = makeCategory();

        insert new Budget_Lock__c(
            Scope_Level__c = 'Global', Period_Year__c = 2025, Is_Active__c = true
        );

        Test.startTest();
        BudgetLockService.LockResult result =
            BudgetLockService.checkLock(acct.Id, cat.Id, 'Digital', 2026);
        Test.stopTest();

        System.assertEquals(false, result.isLocked, 'Lock for a different year should not apply');
    }

    // ── Office/Market/Region scopes do not currently block ────────────────────

    @IsTest
    static void testOfficeScopeIsNonBlocking() {
        Account acct = makeAccount();
        Category__c cat = makeCategory();

        // Office scope lock — Office__c field is deferred to a future slice;
        // the 'Office' scope level should still be non-blocking.
        insert new Budget_Lock__c(
            Scope_Level__c = 'Office',
            Period_Year__c = 2026, Is_Active__c = true
        );

        Test.startTest();
        BudgetLockService.LockResult result =
            BudgetLockService.checkLock(acct.Id, cat.Id, 'Digital', 2026);
        Test.stopTest();

        System.assertEquals(false, result.isLocked,
            'Office-scoped lock is non-blocking until Account.Office__c lookup is wired');
    }
}
