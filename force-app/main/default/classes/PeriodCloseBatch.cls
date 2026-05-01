/**
 * Async batch job for large-period snapshot generation.
 *
 * Launched by PeriodCloseController.closePeriodAsync when the period has
 * > SYNC_THRESHOLD projections — otherwise PeriodCloseService.doClose handles
 * it synchronously.
 *
 * Each execute() chunk inserts/upserts Period_Snapshot__c rows for one page of
 * Projection__c records, then the finish() method updates Period_Close__c.Status__c
 * to Closed and stamps Closed_At__c.
 */
public with sharing class PeriodCloseBatch implements Database.Batchable<SObject>, Database.Stateful {

    /** Periods with fewer projections than this are closed synchronously. */
    @TestVisible
    public static final Integer SYNC_THRESHOLD = 200;

    private final Id    periodCloseId;
    private       Integer snapshotsCreated = 0;

    public PeriodCloseBatch(Id periodCloseId) {
        this.periodCloseId = periodCloseId;
    }

    // ── Batchable interface ───────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Period_Close__c pc = [
            SELECT Period_Year__c, Period_Month__c
            FROM   Period_Close__c
            WHERE  Id = :periodCloseId
        ];
        return Database.getQueryLocator([
            SELECT Id, Account__c, Category__c, Revenue_Type__c,
                   Period_Year__c, Period_Month__c, Amount__c, Actual_Amount__c
            FROM   Projection__c
            WHERE  Period_Year__c  = :pc.Period_Year__c
              AND  Period_Month__c = :pc.Period_Month__c
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Projection__c> projections) {
        List<Period_Snapshot__c> snapshots = new List<Period_Snapshot__c>();
        for (Projection__c proj : projections) {
            snapshots.add(new Period_Snapshot__c(
                Period_Close__c           = periodCloseId,
                Projection__c             = proj.Id,
                Account__c                = proj.Account__c,
                Category__c               = proj.Category__c,
                Revenue_Type__c           = proj.Revenue_Type__c,
                Period_Year__c            = proj.Period_Year__c,
                Period_Month__c           = proj.Period_Month__c,
                Projected_At_Close__c     = proj.Amount__c        != null ? proj.Amount__c        : 0,
                Actual_At_Close__c        = proj.Actual_Amount__c != null ? proj.Actual_Amount__c : 0,
                Snapshot_Composite_Key__c = periodCloseId + '|' + proj.Id
            ));
        }
        if (!snapshots.isEmpty()) {
            Database.UpsertResult[] results =
                Database.upsert(snapshots, Period_Snapshot__c.Snapshot_Composite_Key__c, false);
            for (Database.UpsertResult r : results) {
                if (r.isSuccess()) snapshotsCreated++;
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        Period_Close__c pc = new Period_Close__c(
            Id           = periodCloseId,
            Status__c    = 'Closed',
            Closed_At__c = Datetime.now()
        );
        update pc;
    }
}
