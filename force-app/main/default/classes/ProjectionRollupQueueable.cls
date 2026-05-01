/**
 * Async queueable that aggregates Actual_Revenue__c amounts onto matching
 * Projection__c records (Projection__c.Actual_Amount__c).
 *
 * Triggered by ReconciliationEngine after a successful batch upsert.
 * Uses the same Account+Category+RevenueType+Year+Month composite key that
 * Projection__c already uses (Composite_Key__c).
 *
 * Governor limit safety: processes up to MAX_ACTUALS_PER_JOB actuals per
 * enqueue; if the input set is larger, this job chains itself for the remainder.
 */
public with sharing class ProjectionRollupQueueable implements Queueable {

    @TestVisible
    static final Integer MAX_ACTUALS_PER_JOB = 2000;

    private final List<Id> actualIds;
    private final Integer  offset;

    public ProjectionRollupQueueable(Set<Id> actualIds) {
        this(new List<Id>(actualIds), 0);
    }

    private ProjectionRollupQueueable(List<Id> actualIds, Integer offset) {
        this.actualIds = actualIds;
        this.offset    = offset;
    }

    public void execute(QueueableContext ctx) {
        Integer batchEnd = Math.min(offset + MAX_ACTUALS_PER_JOB, actualIds.size());
        List<Id> chunk = new List<Id>();
        for (Integer i = offset; i < batchEnd; i++) chunk.add(actualIds[i]);

        rollup(chunk);

        // Chain if more records remain
        if (batchEnd < actualIds.size()) {
            System.enqueueJob(new ProjectionRollupQueueable(actualIds, end));
        }
    }

    // ── Core rollup logic ─────────────────────────────────────────────────────

    @TestVisible
    static void rollup(List<Id> actualIds) {
        if (actualIds == null || actualIds.isEmpty()) return;

        // Fetch actuals with all dimension fields
        List<Actual_Revenue__c> actuals = [
            SELECT Id, Account__c, Category__c, Revenue_Type__c,
                   Period_Year__c, Period_Month__c, Revenue_Amount__c
            FROM   Actual_Revenue__c
            WHERE  Id IN :actualIds
              AND  Account__c  != null
              AND  Category__c != null
        ];

        // Aggregate amounts by composite key
        Map<String, Decimal> keyToAmount = new Map<String, Decimal>();
        for (Actual_Revenue__c a : actuals) {
            String key = ProjectionTriggerHandler.buildCompositeKey(
                new Projection__c(
                    Account__c      = a.Account__c,
                    Category__c     = a.Category__c,
                    Revenue_Type__c = a.Revenue_Type__c,
                    Period_Year__c  = a.Period_Year__c,
                    Period_Month__c = a.Period_Month__c
                )
            );
            Decimal existing = keyToAmount.containsKey(key) ? keyToAmount.get(key) : 0;
            keyToAmount.put(key, existing + (a.Revenue_Amount__c != null ? a.Revenue_Amount__c : 0));
        }

        if (keyToAmount.isEmpty()) return;

        // Find existing Projection__c rows that match
        List<Projection__c> existingProjs = [
            SELECT Id, Composite_Key__c, Account__c, Category__c,
                   Revenue_Type__c, Period_Year__c, Period_Month__c, Actual_Amount__c
            FROM   Projection__c
            WHERE  Composite_Key__c IN :keyToAmount.keySet()
        ];

        Map<String, Projection__c> existingByKey = new Map<String, Projection__c>();
        for (Projection__c p : existingProjs) {
            existingByKey.put(p.Composite_Key__c, p);
        }

        // Build upsert list: update existing or create new stub with Amount=0
        List<Projection__c> toUpsert = new List<Projection__c>();
        for (String key : keyToAmount.keySet()) {
            Projection__c proj;
            if (existingByKey.containsKey(key)) {
                proj = existingByKey.get(key);
            } else {
                // Parse key: AccountId|CategoryId|RevenueType|Year|Month
                List<String> parts = key.split('\\|');
                if (parts.size() < 5) continue;
                proj = new Projection__c(
                    Account__c       = parts[0],
                    Category__c      = parts[1],
                    Revenue_Type__c  = parts[2],
                    Period_Year__c   = Decimal.valueOf(parts[3]),
                    Period_Month__c  = Decimal.valueOf(parts[4]),
                    Amount__c        = 0,
                    Stage__c         = 'Working',
                    Composite_Key__c = key
                );
            }
            proj.Actual_Amount__c = keyToAmount.get(key);
            toUpsert.add(proj);
        }

        if (!toUpsert.isEmpty()) {
            Database.upsert(toUpsert, Projection__c.Composite_Key__c, false);
        }
    }
}
