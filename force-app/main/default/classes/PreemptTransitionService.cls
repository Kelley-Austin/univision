/**
 * Detects preempt → booked supersedes and preempt cancellations among newly
 * upserted Actual_Revenue__c records and writes immutable Preempt_Transition_Log__c
 * audit rows.
 *
 * Match key: Source_Order_Number__c + Period_Year__c + Period_Month__c + Calendar_Type__c.
 *
 * Behaviors:
 *   • Booked actual (Is_Preempt__c = false) with a populated Source_Order_Number__c
 *     finds prior Active preempts on the same key and marks them Superseded.
 *   • Cancellation actual (Is_Preempt__c = true, Preempt_Status__c = 'Cancelled')
 *     finds prior Active preempts on the same key and marks them Superseded;
 *     no booked amount is applied.
 *
 * The state mutation (mark Superseded) and audit insert run in a single
 * Database.update + insert pair so failure leaves no half-applied transitions.
 *
 * Called by ReconciliationEngine.reconcileBatch after Actual_Revenue__c upsert
 * and before ProjectionRollupQueueable enqueue. The rollup is responsible for
 * excluding Superseded/Cancelled actuals from projection sums.
 */
public with sharing class PreemptTransitionService {

    @TestVisible
    private static final String STATUS_ACTIVE     = 'Active';
    @TestVisible
    private static final String STATUS_SUPERSEDED = 'Superseded';
    @TestVisible
    private static final String STATUS_CANCELLED  = 'Cancelled';

    @TestVisible
    private static final String TYPE_SUPERSEDE   = 'Supersede';
    @TestVisible
    private static final String TYPE_CANCELLATION = 'Cancellation';

    /**
     * Inspect upserted actuals for preempt transitions. No-op when input is
     * empty or no triggering rows are found.
     */
    public static void process(Set<Id> upsertedActualIds) {
        if (upsertedActualIds == null || upsertedActualIds.isEmpty()) return;

        // Pull only the fields needed; filter to triggering rows in SOQL.
        List<Actual_Revenue__c> triggers = [
            SELECT Id, Is_Preempt__c, Preempt_Status__c, Source_Order_Number__c,
                   Period_Year__c, Period_Month__c, Calendar_Type__c, Revenue_Amount__c
            FROM   Actual_Revenue__c
            WHERE  Id IN :upsertedActualIds
              AND  Source_Order_Number__c != null
              AND  ( (Is_Preempt__c = false)
                  OR (Is_Preempt__c = true AND Preempt_Status__c = :STATUS_CANCELLED) )
        ];
        if (triggers.isEmpty()) return;

        // Collect distinct match keys so we can fetch all prior Active preempts in one SOQL.
        Set<String> orderNumbers = new Set<String>();
        for (Actual_Revenue__c t : triggers) orderNumbers.add(t.Source_Order_Number__c);

        Map<String, List<Actual_Revenue__c>> priorByKey = new Map<String, List<Actual_Revenue__c>>();
        for (Actual_Revenue__c p : [
            SELECT Id, Source_Order_Number__c, Period_Year__c, Period_Month__c,
                   Calendar_Type__c, Revenue_Amount__c, Preempt_Status__c
            FROM   Actual_Revenue__c
            WHERE  Source_Order_Number__c IN :orderNumbers
              AND  Is_Preempt__c = true
              AND  Preempt_Status__c = :STATUS_ACTIVE
              AND  Id NOT IN :upsertedActualIds
        ]) {
            String key = matchKey(p.Source_Order_Number__c, p.Period_Year__c, p.Period_Month__c, p.Calendar_Type__c);
            List<Actual_Revenue__c> bucket = priorByKey.get(key);
            if (bucket == null) { bucket = new List<Actual_Revenue__c>(); priorByKey.put(key, bucket); }
            bucket.add(p);
        }

        if (priorByKey.isEmpty()) return;

        List<Actual_Revenue__c> toUpdate = new List<Actual_Revenue__c>();
        Set<Id> alreadyMarked = new Set<Id>();
        List<Preempt_Transition_Log__c> logs = new List<Preempt_Transition_Log__c>();

        for (Actual_Revenue__c trig : triggers) {
            String key = matchKey(trig.Source_Order_Number__c, trig.Period_Year__c, trig.Period_Month__c, trig.Calendar_Type__c);
            List<Actual_Revenue__c> priors = priorByKey.get(key);
            if (priors == null || priors.isEmpty()) continue;

            Boolean isCancellation = trig.Is_Preempt__c == true && trig.Preempt_Status__c == STATUS_CANCELLED;
            String  txType         = isCancellation ? TYPE_CANCELLATION : TYPE_SUPERSEDE;
            Decimal appliedAmt     = isCancellation ? 0 : nz(trig.Revenue_Amount__c);

            for (Actual_Revenue__c p : priors) {
                if (alreadyMarked.contains(p.Id)) continue;
                alreadyMarked.add(p.Id);

                p.Preempt_Status__c = STATUS_SUPERSEDED;
                toUpdate.add(p);

                logs.add(new Preempt_Transition_Log__c(
                    Original_Preempt__c    = p.Id,
                    Booked_Actual__c       = isCancellation ? null : trig.Id,
                    Transition_Type__c     = txType,
                    Reversed_Amount__c     = nz(p.Revenue_Amount__c),
                    Applied_Amount__c      = appliedAmt,
                    Source_Order_Number__c = trig.Source_Order_Number__c,
                    Period_Year__c         = trig.Period_Year__c,
                    Period_Month__c        = trig.Period_Month__c,
                    Calendar_Type__c       = trig.Calendar_Type__c
                ));
            }
        }

        if (toUpdate.isEmpty()) return;

        // Atomicity: mark and audit in one savepoint so a failed audit insert rolls back the supersede.
        Savepoint sp = Database.setSavepoint();
        try {
            update toUpdate;
            insert logs;
        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }
    }

    @TestVisible
    private static String matchKey(String orderNumber, Decimal year, Decimal month, String calendarType) {
        return String.join(new List<String>{
            orderNumber == null ? '' : orderNumber,
            year  == null ? '' : String.valueOf(year.intValue()),
            month == null ? '' : String.valueOf(month.intValue()),
            calendarType == null ? '' : calendarType
        }, '|');
    }

    private static Decimal nz(Decimal v) { return v == null ? 0 : v; }
}
