/**
 * =============================================================================
 *  PeriodCloseTriggerHandler — State-machine guard for Period_Close__c
 * =============================================================================
 *
 *  Purpose
 *  -------
 *  Period_Close__c records progress through a constrained set of statuses.
 *  Without a guard, an admin or integration could move a row from Closed back
 *  to Open, silently invalidating downstream snapshots and locking logic. This
 *  handler rejects every transition that isn't on the allow-list.
 *
 *  Valid transitions
 *  -----------------
 *      Open     → Closed     (close the period)
 *      Closed   → Reopened   (reopen a past period for late corrections)
 *      Reopened → Closed     (re-close after the corrections land)
 *
 *  Blocked
 *  -------
 *      Closed   → Open       (no going back to Open after a close)
 *      Reopened → Open       (same — must go via Closed)
 *      Any      → Reopened   when Period_Year__c / Period_Month__c is in the
 *                            future (can't reopen a period that hasn't closed)
 *      Any      → unknown    (catches accidental new picklist values)
 *
 *  Why the rank-based map isn't used here
 *  --------------------------------------
 *  The Projection forecast-stage handler uses a rank map because the stages
 *  form a partial order (NA can transition either way, the rest are linear).
 *  Period close is *not* linear (Closed↔Reopened is bidirectional), so we
 *  enumerate the allowed pairs explicitly. Tempting to "simplify" with a rank
 *  comparison — don't. This shape mirrors the actual rule.
 *
 *  Test contract
 *  -------------
 *  isValidTransition(String, String) is invoked directly from
 *  PeriodCloseTriggerHandlerTest. Its signature is part of our test surface;
 *  do not rename or change visibility without updating the tests.
 * =============================================================================
 */
public with sharing class PeriodCloseTriggerHandler extends TriggerHandler {

    // =========================================================================
    //  Phase methods
    // =========================================================================

    protected override void beforeUpdate() {
        validateTransitions(
            (List<Period_Close__c>) Trigger.new,
            (Map<Id, Period_Close__c>) Trigger.oldMap
        );
    }

    // =========================================================================
    //  Validation
    // =========================================================================

    /**
     * For each row, compare prior Status__c (from oldMap) to the new value:
     *   * if unchanged, skip
     *   * if not on the allow-list, addError (record-level — DML aborts)
     *   * if reopening, also block when Period_Year__c/Period_Month__c is in
     *     the future relative to today
     */
    @TestVisible
    private static void validateTransitions(
        List<Period_Close__c> records,
        Map<Id, Period_Close__c> oldMap
    ) {
        if (oldMap == null) return;

        Date today = Date.today();
        Integer currentYear  = today.year();
        Integer currentMonth = today.month();

        for (Period_Close__c pc : records) {
            Period_Close__c old = oldMap.get(pc.Id);
            if (old == null) continue;

            String prevStatus = old.Status__c;
            String toStatus   = pc.Status__c;

            // No-op: the trigger fires for any update; only react when status changed.
            if (prevStatus == toStatus) continue;

            if (!isValidTransition(prevStatus, toStatus)) {
                pc.addError(
                    'Invalid status transition: ' + prevStatus + ' → ' + toStatus +
                    '. Allowed: Open→Closed, Closed→Reopened, Reopened→Closed.'
                );
                continue;
            }

            // Even on a valid transition, block reopening a future period.
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

    /**
     * Pure function: returns true if (prevStatus → toStatus) is on the allow-list.
     *
     * NOTE: signature is preserved for backwards compatibility with existing
     * unit tests in PeriodCloseTriggerHandlerTest. Do not change.
     */
    @TestVisible
    static Boolean isValidTransition(String prevStatus, String toStatus) {
        if (prevStatus == 'Open'     && toStatus == 'Closed')   return true;
        if (prevStatus == 'Closed'   && toStatus == 'Reopened') return true;
        if (prevStatus == 'Reopened' && toStatus == 'Closed')   return true;
        return false;
    }
}
