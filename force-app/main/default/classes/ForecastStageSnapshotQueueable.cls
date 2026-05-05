/**
 * Iterates Projections and writes a Forecast_Stage_Snapshot__c per row, using
 * the current Forecast_Stage__c plus its weight from Forecast_Stage_Weight__mdt.
 *
 * Run weekly by ForecastStageSnapshotScheduler (Sunday 23:59 org-time). Chunks
 * itself at 200 rows per Queueable to stay inside DML and CPU limits, then
 * chains for the remainder.
 */
public with sharing class ForecastStageSnapshotQueueable implements Queueable {

    @TestVisible
    static final Integer CHUNK_SIZE = 200;

    private final Date    snapshotDate;
    private final Integer offset;

    public ForecastStageSnapshotQueueable() {
        this(Date.today(), 0);
    }

    public ForecastStageSnapshotQueueable(Date snapshotDate) {
        this(snapshotDate, 0);
    }

    private ForecastStageSnapshotQueueable(Date snapshotDate, Integer offset) {
        this.snapshotDate = snapshotDate;
        this.offset       = offset;
    }

    public void execute(QueueableContext ctx) {
        Map<String, Decimal> weights = ForecastStageWeightProvider.getWeights();

        List<Projection__c> projections = [
            SELECT Id, Forecast_Stage__c, Amount__c
            FROM   Projection__c
            ORDER BY Id
            LIMIT :CHUNK_SIZE
            OFFSET :offset
        ];
        if (projections.isEmpty()) return;

        List<Forecast_Stage_Snapshot__c> snapshots = new List<Forecast_Stage_Snapshot__c>();
        for (Projection__c p : projections) {
            String stage = String.isNotBlank(p.Forecast_Stage__c) ? p.Forecast_Stage__c : 'Stage 0';
            Decimal weight = weights.containsKey(stage) ? weights.get(stage) : 0;
            snapshots.add(new Forecast_Stage_Snapshot__c(
                Projection__c    = p.Id,
                Snapshot_Date__c = snapshotDate,
                Forecast_Stage__c = stage,
                Weight_Pct__c    = weight,
                Amount__c        = p.Amount__c
            ));
        }
        insert snapshots;

        if (projections.size() == CHUNK_SIZE) {
            System.enqueueJob(new ForecastStageSnapshotQueueable(snapshotDate, offset + CHUNK_SIZE));
        }
    }
}
