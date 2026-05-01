/**
 * Validates Period_Close__c state-machine transitions before DML commits.
 *
 * Valid transitions:
 *   Open     → Closed    (close the period)
 *   Closed   → Reopened  (reopen a past period)
 *   Reopened → Closed    (re-close after correction)
 *
 * Blocked:
 *   Closed/Reopened → Open  (cannot go back to Open)
 *   Any → any other         (invalid picklist value)
 *   Closed   → Reopened when Year+Month is in the future
 */
public with sharing class PeriodCloseTriggerHandler {

    // ── Entry point called from trigger ───────────────────────────────────────

    public static void handleBeforeUpdate(
        List<Period_Close__c> newList,
        Map<Id, Period_Close__c> oldMap
    ) {
        Date today = Date.today();
        Integer currentYear  = today.year();
        Integer currentMonth = today.month();

        for (Period_Close__c pc : newList) {
            Period_Close__c old = oldMap.get(pc.Id);
            String fromStatus = old.Status__c;
            String toStatus   = pc.Status__c;

            if (fromStatus == toStatus) continue; // no status change — skip

            if (!isValidTransition(fromStatus, toStatus)) {
                pc.addError(
                    'Invalid status transition: ' + fromStatus + ' → ' + toStatus +
                    '. Allowed: Open→Closed, Closed→Reopened, Reopened→Closed.'
                );
                continue;
            }

            // Block reopening a future period
            if (toStatus == 'Reopened') {
                Integer year  = pc.Period_Year__c  != null ? pc.Period_Year__c.intValue()  : 0;
                Integer month = pc.Period_Month__c != null ? pc.Period_Month__c.intValue() : 0;
                if (year > currentYear || (year == currentYear && month > currentMonth)) {
                    pc.addError(
                        'Cannot reopen a future period (' + month + '/' + year + ').'
                    );
                }
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    @TestVisible
    static Boolean isValidTransition(String fromStatus, String toStatus) {
        if (fromStatus == 'Open'     && toStatus == 'Closed')   return true;
        if (fromStatus == 'Closed'   && toStatus == 'Reopened') return true;
        if (fromStatus == 'Reopened' && toStatus == 'Closed')   return true;
        return false;
    }
}
