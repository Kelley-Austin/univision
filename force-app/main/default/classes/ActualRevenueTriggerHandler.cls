/**
 * Handler for ActualRevenueTrigger.
 *
 * Before insert:
 *   - Populates Category_Snapshot__c from Category__r.Name (immutable; skipped on update).
 *   - Sets Is_Late__c = true when today is after the Period_Close__c.Close_Date__c for
 *     the matching Period_Month__c + Period_Year__c.
 *
 * Before update:
 *   - Prevents Category_Snapshot__c from being changed once set.
 *   - Re-evaluates Is_Late__c in case the record's period fields are corrected.
 */
public with sharing class ActualRevenueTriggerHandler {

    public static void handle(
        List<Actual_Revenue__c> newList,
        Map<Id, Actual_Revenue__c> oldMap,
        Boolean isInsert
    ) {
        // Collect Category IDs so we can query names in one SOQL
        Set<Id> catIds = new Set<Id>();
        for (Actual_Revenue__c a : newList) {
            if (a.Category__c != null) catIds.add(a.Category__c);
        }
        Map<Id, String> catNames = new Map<Id, String>();
        if (!catIds.isEmpty()) {
            for (Category__c cat : [SELECT Id, Name FROM Category__c WHERE Id IN :catIds]) {
                catNames.put(cat.Id, cat.Name);
            }
        }

        // Build a key set of Year|Month for period close lookup
        Set<String> periodKeys = new Set<String>();
        for (Actual_Revenue__c a : newList) {
            if (a.Period_Year__c != null && a.Period_Month__c != null) {
                periodKeys.add(a.Period_Year__c + '|' + a.Period_Month__c);
            }
        }
        // Map of 'Year|Month' → close date
        Map<String, Date> closeDates = new Map<String, Date>();
        if (!periodKeys.isEmpty()) {
            for (Period_Close__c pc : [
                SELECT Period_Year__c, Period_Month__c, Close_Date__c
                FROM   Period_Close__c
                WHERE  Status__c = 'Closed'
            ]) {
                String key = pc.Period_Year__c + '|' + pc.Period_Month__c;
                closeDates.put(key, pc.Close_Date__c);
            }
        }

        Date today = Date.today();

        for (Actual_Revenue__c a : newList) {
            // ── Category Snapshot (insert only; immutable) ────────────────────
            if (isInsert) {
                if (a.Category__c != null && catNames.containsKey(a.Category__c)) {
                    a.Category_Snapshot__c = catNames.get(a.Category__c);
                }
            } else {
                // On update: restore the original snapshot to prevent changes
                Actual_Revenue__c old = oldMap != null ? oldMap.get(a.Id) : null;
                if (old != null && String.isNotBlank(old.Category_Snapshot__c)) {
                    a.Category_Snapshot__c = old.Category_Snapshot__c;
                }
            }

            // ── Is Late flag ──────────────────────────────────────────────────
            if (a.Period_Year__c != null && a.Period_Month__c != null) {
                String key = a.Period_Year__c + '|' + a.Period_Month__c;
                if (closeDates.containsKey(key)) {
                    a.Is_Late__c = today.daysBetween(closeDates.get(key)) < 0;
                } else {
                    a.Is_Late__c = false;
                }
            }
        }
    }
}
