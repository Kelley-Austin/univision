public with sharing class BudgetLockService {

    public class LockResult {
        public Boolean isLocked    { get; set; }
        public String  lockMessage { get; set; }
        public String  scopeLevel  { get; set; }
        public LockResult() { isLocked = false; lockMessage = ''; scopeLevel = ''; }
    }

    /**
     * Returns a LockResult for the given projection context. The check walks from the
     * broadest scope (Global) down to the narrowest (Account, Category) and short-circuits
     * on the first active lock that matches.
     */
    @AuraEnabled(cacheable=true)
    public static LockResult checkLock(Id accountId, Id categoryId, String revenueType, Integer periodYear) {
        List<Budget_Lock__c> locks = [
            SELECT Id, Scope_Level__c, Account__c, Category__c, Office__c,
                   Revenue_Type__c, Is_Active__c, Lock_Message__c
            FROM   Budget_Lock__c
            WHERE  Is_Active__c = true
              AND  Period_Year__c = :periodYear
            ORDER BY Scope_Level__c
        ];

        LockResult result = new LockResult();
        for (Budget_Lock__c lock : locks) {
            if (!revenueTypeMatches(lock.Revenue_Type__c, revenueType)) {
                continue;
            }
            if (scopeMatches(lock, accountId, categoryId)) {
                result.isLocked    = true;
                result.lockMessage = String.isNotBlank(lock.Lock_Message__c)
                    ? lock.Lock_Message__c
                    : 'Budget is locked at the ' + lock.Scope_Level__c + ' level.';
                result.scopeLevel  = lock.Scope_Level__c;
                return result;
            }
        }
        return result;
    }

    private static Boolean revenueTypeMatches(String lockType, String requestType) {
        // Blank lock revenue type means "all types"
        return String.isBlank(lockType) || lockType == requestType;
    }

    private static Boolean scopeMatches(Budget_Lock__c lock, Id accountId, Id categoryId) {
        switch on lock.Scope_Level__c {
            when 'Global' {
                return true;
            }
            when 'Account' {
                return lock.Account__c == accountId;
            }
            when 'Category' {
                return lock.Category__c == categoryId;
            }
            when 'Office' {
                // Office match requires Account → Office lookup; resolved in a future slice.
                // For now, Office-scoped locks are non-blocking until Account.Office__c is wired.
                return false;
            }
            when 'Market', 'Region' {
                // Market and Region require territory hierarchy; non-blocking until that slice lands.
                return false;
            }
            when else {
                return false;
            }
        }
    }
}
