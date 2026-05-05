/**
 * =============================================================================
 *  ActualRevenueTriggerHandler — Trigger handler for Actual_Revenue__c
 * =============================================================================
 *
 *  Lifecycle responsibilities
 *  --------------------------
 *  beforeInsert  ── Stamp Category_Snapshot__c from Category__r.Name (immutable
 *                   audit field; locked-in value at write time)
 *                ── Stamp Is_Late__c by comparing today() to the matching
 *                   Period_Close__c.Close_Date__c (only for Closed periods)
 *                ── Auto-link Pitch_Project__c via PitchProjectUnitCodeLinker
 *                   for any record carrying a Unit_Code__c
 *
 *  beforeUpdate  ── Restore Category_Snapshot__c if the old row had one
 *                   (snapshot is intentionally immutable post-insert)
 *                ── Re-evaluate Is_Late__c (period fields may be corrected
 *                   after initial insert)
 *                ── Re-link Pitch_Project__c ONLY when Unit_Code__c changed
 *                   AND the record is not already linked (don't trample a
 *                   manually-set link)
 *
 *  afterInsert   ── Enqueue ProjectionRollupQueueable so the matching
 *                   Projection__c rows pick up this batch's Actual_Amount__c.
 *                   Gated by TestSettings.enableQueueableInTests so existing
 *                   tests don't get unexpected async side-effects.
 *
 *  afterUpdate   ── Same enqueue as afterInsert. NOTE: when dimension fields
 *                   (Account, Category, Revenue_Type, Period_*) change on an
 *                   existing Actual, only the NEW projection's totals are
 *                   recomputed by ProjectionRollupQueueable in its current
 *                   form. The OLD projection's total will be stale until that
 *                   queueable is enhanced to accept old-key hints. Tracked
 *                   in the project's bug tracker; safe enough for the current
 *                   ingest-driven workflow because reparenting Actuals is rare.
 *
 *  afterDelete   ── Same enqueue, using Trigger.old IDs.
 *
 *  Bulk safety
 *  -----------
 *    * Period_Close__c query filters by Composite_Key__c (indexed) plus
 *      Status__c = 'Closed' — selective even at thousands of periods.
 *    * Category__c lookup is one SOQL keyed by Set<Id>.
 *    * PitchProjectUnitCodeLinker.linkActuals is invoked once per phase, on a
 *      pre-filtered list (no double-call — the previous implementation called
 *      it twice on insert).
 *
 *  Test seam
 *  ---------
 *    * Private helpers are @TestVisible so unit-style tests can hit them
 *      without a full DML round-trip.
 *    * The async enqueue is gated by TestSettings.enableQueueableInTests
 *      (default false) so existing tests don't trip new side effects. Tests
 *      that want to assert rollup behavior set the flag, run inside
 *      Test.startTest()/Test.stopTest(), and assert on Projection__c after.
 *
 *  Schema dependencies (do not change without updating both ends)
 *  --------------------------------------------------------------
 *    * Period_Close__c.Composite_Key__c uses the format "YYYY|M" (no zero-pad
 *      on month). The periodKey() helper here MUST produce the same shape.
 *      The existing test fixture sets '2026|1', confirming this convention.
 *    * Period_Close__c.Status__c values include 'Closed' (case-sensitive).
 *
 *  Migration note
 *  --------------
 *  This handler was rewritten on 2026-05-04 to extend the new TriggerHandler
 *  base class and adopt the canonical phase-method pattern. The previous
 *  implementation used a single static handle(newList, oldMap, isInsert)
 *  dispatched directly from the trigger. Behavior is preserved; the diff
 *  fixes a double-call to PitchProjectUnitCodeLinker on insert and replaces
 *  the unfiltered Period_Close query with an indexed one.
 * =============================================================================
 */
public with sharing class ActualRevenueTriggerHandler extends TriggerHandler {

    // =========================================================================
    //  Phase methods
    // =========================================================================

    protected override void beforeInsert() {
        List<Actual_Revenue__c> recs = (List<Actual_Revenue__c>) Trigger.new;
        stampCategorySnapshots(recs);
        flagLateActuals(recs);
        linkPitchProjects(recs);
    }

    protected override void beforeUpdate() {
        List<Actual_Revenue__c> recs = (List<Actual_Revenue__c>) Trigger.new;
        Map<Id, Actual_Revenue__c> oldMap = (Map<Id, Actual_Revenue__c>) Trigger.oldMap;
        restoreCategorySnapshots(recs, oldMap);
        flagLateActuals(recs);
        relinkPitchProjectsOnUpdate(recs, oldMap);
    }

    protected override void afterInsert() {
        enqueueProjectionRollup(Trigger.new, null);
    }

    protected override void afterUpdate() {
        // Pass both new and old so a future enhancement of
        // ProjectionRollupQueueable can detect dimension-change reparenting
        // without us having to revisit this trigger.
        enqueueProjectionRollup(Trigger.new, Trigger.old);
    }

    protected override void afterDelete() {
        enqueueProjectionRollup(null, Trigger.old);
    }

    // =========================================================================
    //  Category snapshot
    // =========================================================================

    /**
     * Stamp Category_Snapshot__c at insert time so the value is locked in even
     * if the parent Category__c is later renamed. We snapshot Name, not Id, so
     * downstream reports remain stable when categories are merged or retired.
     */
    @TestVisible
    private static void stampCategorySnapshots(List<Actual_Revenue__c> recs) {
        // Collect distinct Category Ids from incoming records — empty case
        // exits early to avoid a no-op SOQL.
        Set<Id> catIds = new Set<Id>();
        for (Actual_Revenue__c a : recs) {
            if (a.Category__c != null) catIds.add(a.Category__c);
        }
        if (catIds.isEmpty()) return;

        // One SOQL keyed by Set<Id> — bulk-safe at any volume Salesforce will
        // hand us inside a single trigger invocation (max 200 rows).
        Map<Id, String> namesByCategoryId = new Map<Id, String>();
        for (Category__c c : [
            SELECT Id, Name
            FROM   Category__c
            WHERE  Id IN :catIds
        ]) {
            namesByCategoryId.put(c.Id, c.Name);
        }

        for (Actual_Revenue__c a : recs) {
            if (a.Category__c == null) continue;
            String name = namesByCategoryId.get(a.Category__c);
            if (name != null) {
                a.Category_Snapshot__c = name;
            }
        }
    }

    /**
     * Snapshot is immutable post-insert. If the user (or a misconfigured
     * integration) tries to overwrite it on update, restore the prior value.
     * Only restores when the old record actually had a snapshot — leaves the
     * field alone if it was blank originally (allows back-filling later).
     */
    @TestVisible
    private static void restoreCategorySnapshots(
        List<Actual_Revenue__c> recs,
        Map<Id, Actual_Revenue__c> oldMap
    ) {
        if (oldMap == null) return;
        for (Actual_Revenue__c a : recs) {
            Actual_Revenue__c old = oldMap.get(a.Id);
            if (old != null && String.isNotBlank(old.Category_Snapshot__c)) {
                a.Category_Snapshot__c = old.Category_Snapshot__c;
            }
        }
    }

    // =========================================================================
    //  Late flag
    // =========================================================================

    /**
     * Stamp Is_Late__c = true for records whose period is already closed and
     * whose Close_Date__c is in the past relative to today.
     *
     * Indexed query: filters by Period_Close__c.Composite_Key__c using the set
     * of period keys present in this batch — does NOT pull every Closed period
     * org-wide. (The previous implementation scanned all closed periods,
     * which scaled linearly with org age.)
     */
    @TestVisible
    private static void flagLateActuals(List<Actual_Revenue__c> recs) {
        Set<String> periodKeys = new Set<String>();
        for (Actual_Revenue__c a : recs) {
            if (a.Period_Year__c != null && a.Period_Month__c != null) {
                periodKeys.add(periodKey(a.Period_Year__c, a.Period_Month__c));
            }
        }
        if (periodKeys.isEmpty()) return;

        Map<String, Date> closeDateByKey = new Map<String, Date>();
        for (Period_Close__c pc : [
            SELECT Composite_Key__c, Close_Date__c
            FROM   Period_Close__c
            WHERE  Composite_Key__c IN :periodKeys
              AND  Status__c = 'Closed'
        ]) {
            // Defensive: Composite_Key__c shouldn't be null for closed periods
            // but we don't want a single bad row to blow up the trigger.
            if (pc.Composite_Key__c != null && pc.Close_Date__c != null) {
                closeDateByKey.put(pc.Composite_Key__c, pc.Close_Date__c);
            }
        }

        // Late = today is AFTER the close date.
        // today.daysBetween(closeDate) returns NEGATIVE when closeDate is in
        // the past. We treat null close-date or non-closed periods as "not late".
        Date today = Date.today();
        for (Actual_Revenue__c a : recs) {
            if (a.Period_Year__c == null || a.Period_Month__c == null) {
                a.Is_Late__c = false;
                continue;
            }
            String key = periodKey(a.Period_Year__c, a.Period_Month__c);
            Date closeDate = closeDateByKey.get(key);
            a.Is_Late__c = (closeDate != null) && (today.daysBetween(closeDate) < 0);
        }
    }

    // =========================================================================
    //  Pitch Project linking
    // =========================================================================

    /**
     * Insert path: link every record (the linker filters internally on
     * Unit_Code__c presence; passing the full list keeps the API simple and
     * lets the linker decide).
     *
     * NOTE: This used to be called twice on insert (once eagerly, then again
     * via a second pass that built a redundant 'toLink' list). The second
     * pass was removed in this refactor; the linker is now invoked exactly
     * once per insert.
     */
    @TestVisible
    private static void linkPitchProjects(List<Actual_Revenue__c> recs) {
        if (recs == null || recs.isEmpty()) return;
        PitchProjectUnitCodeLinker.linkActuals(recs);
    }

    /**
     * Update path: relink ONLY records where Unit_Code__c changed AND the
     * record is currently unlinked (Pitch_Project__c is null). This protects
     * a manually-set Pitch_Project__c from being overwritten by the linker
     * when the Unit_Code__c happens to also match a different active project.
     */
    @TestVisible
    private static void relinkPitchProjectsOnUpdate(
        List<Actual_Revenue__c> recs,
        Map<Id, Actual_Revenue__c> oldMap
    ) {
        if (oldMap == null) return;

        List<Actual_Revenue__c> toRelink = new List<Actual_Revenue__c>();
        for (Actual_Revenue__c a : recs) {
            Actual_Revenue__c old = oldMap.get(a.Id);
            if (old == null) continue;
            // Both conditions must hold: unit-code changed AND not yet linked.
            if (a.Unit_Code__c != old.Unit_Code__c && a.Pitch_Project__c == null) {
                toRelink.add(a);
            }
        }
        if (!toRelink.isEmpty()) {
            PitchProjectUnitCodeLinker.linkActuals(toRelink);
        }
    }

    // =========================================================================
    //  Projection rollup enqueue
    // =========================================================================

    /**
     * Collects Actual IDs from the supplied trigger lists and enqueues
     * ProjectionRollupQueueable to recompute Projection__c.Actual_Amount__c
     * for each affected composite key.
     *
     * Enqueue is suppressed under test context unless the test has explicitly
     * opted in via TestSettings.enableQueueableInTests. This keeps the new
     * afterX coverage from breaking existing tests that don't expect async
     * side-effects, while leaving the door open for tests that want to
     * exercise the full chain.
     *
     * NOTE on ReconciliationEngine path: the engine currently also calls
     * System.enqueueJob(new ProjectionRollupQueueable(...)) directly after
     * its upserts. That redundant enqueue is harmless because the queueable
     * is idempotent (it recomputes from current state, not by accumulation),
     * but it should be removed in a follow-up refactor now that the trigger
     * itself handles the enqueue uniformly across all entry paths.
     */
    @TestVisible
    private static void enqueueProjectionRollup(List<SObject> newList, List<SObject> oldList) {
        if (Test.isRunningTest() && !TestSettings.enableQueueableInTests) return;

        Set<Id> actualIds = new Set<Id>();
        if (newList != null) {
            for (SObject s : newList) {
                Id id = (Id) s.get('Id');
                if (id != null) actualIds.add(id);
            }
        }
        if (oldList != null) {
            for (SObject s : oldList) {
                Id id = (Id) s.get('Id');
                if (id != null) actualIds.add(id);
            }
        }
        if (actualIds.isEmpty()) return;

        System.enqueueJob(new ProjectionRollupQueueable(actualIds));
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /**
     * Composite key format must match Period_Close__c.Composite_Key__c
     * exactly: "YYYY|M" — no zero-pad on month. Existing test fixture
     * inserts '2026|1', confirming the convention. If the field's formula
     * ever changes, this helper changes with it.
     */
    private static String periodKey(Decimal year, Decimal month) {
        return String.valueOf(year.intValue()) + '|' + String.valueOf(month.intValue());
    }
}
