/**
 * Batch class that promotes Pending Actuals_Record__c rows created by
 * CounterpointIngestionService.
 *
 * For each chunk:
 *  - Rows whose Counterpoint_Order_ID__c already exists on a Processed record
 *    from a different batch are marked Duplicate (cross-batch dedup).
 *  - Remaining Pending rows are marked Processed.
 *
 * Enqueued automatically by CounterpointIngestionService after a successful parse.
 * Can also be launched manually: Database.executeBatch(new CounterpointIngestionBatch(batchId), 200)
 */
public with sharing class CounterpointIngestionBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private final String importBatchId;
    private Integer processed  = 0;
    private Integer promoted   = 0;
    private Integer duplicates = 0;
    private Integer errors     = 0;

    public CounterpointIngestionBatch(String importBatchId) {
        this.importBatchId = importBatchId;
    }

    // ── Batchable interface ───────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Counterpoint_Order_ID__c, Import_Batch_ID__c,
                   Validation_Status__c
            FROM   Actuals_Record__c
            WHERE  Import_Batch_ID__c    = :importBatchId
              AND  Validation_Status__c  = 'Pending'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Actuals_Record__c> scope) {
        // Collect order IDs in this chunk that are candidates for promotion
        Set<String> incomingIds = new Set<String>();
        for (Actuals_Record__c rec : scope) {
            if (String.isNotBlank(rec.Counterpoint_Order_ID__c)) {
                incomingIds.add(rec.Counterpoint_Order_ID__c);
            }
        }

        // Cross-batch duplicate check: find any already-Processed records
        // with the same order ID coming from a DIFFERENT import run
        Set<String> alreadyProcessed = new Set<String>();
        for (Actuals_Record__c existing : [
            SELECT Counterpoint_Order_ID__c
            FROM   Actuals_Record__c
            WHERE  Counterpoint_Order_ID__c IN :incomingIds
              AND  Validation_Status__c      = 'Processed'
              AND  Import_Batch_ID__c       != :importBatchId
        ]) {
            alreadyProcessed.add(existing.Counterpoint_Order_ID__c);
        }

        List<Actuals_Record__c> toUpdate = new List<Actuals_Record__c>();

        for (Actuals_Record__c rec : scope) {
            processed++;
            if (alreadyProcessed.contains(rec.Counterpoint_Order_ID__c)) {
                rec.Validation_Status__c = 'Duplicate';
                rec.Validation_Error__c  = 'CROSS_BATCH_DUPLICATE: order ID '
                    + rec.Counterpoint_Order_ID__c + ' was already imported in a prior batch.';
                duplicates++;
            } else {
                rec.Validation_Status__c = 'Processed';
                promoted++;
            }
            toUpdate.add(rec);
        }

        Database.SaveResult[] results = Database.update(toUpdate, false);
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                errors++;
                promoted = Math.max(0, promoted - 1);
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'CounterpointIngestionBatch [' + importBatchId + '] complete'
            + ' — processed: '  + processed
            + ', promoted: '    + promoted
            + ', duplicates: '  + duplicates
            + ', errors: '      + errors);
    }
}
