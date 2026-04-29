/**
 * Batch class that drives ReconciliationEngine over all Pending staging rows.
 *
 * Run manually:  Database.executeBatch(new ReconciliationBatch(), 200);
 * Or schedule nightly via a Scheduled Apex class.
 *
 * Optionally scope to a specific source system or load batch:
 *   new ReconciliationBatch(sourceSystemId, loadBatchId)
 */
public with sharing class ReconciliationBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private final Id     sourceSystemId;
    private final Id     loadBatchId;
    private       String sourceSystemCode;

    private Integer totalMatched   = 0;
    private Integer totalUnmatched = 0;
    private Integer totalExcluded  = 0;
    private Integer totalErrors    = 0;

    public ReconciliationBatch() {
        this(null, null);
    }

    public ReconciliationBatch(Id sourceSystemId, Id loadBatchId) {
        this.sourceSystemId = sourceSystemId;
        this.loadBatchId    = loadBatchId;
    }

    // ── Batchable interface ───────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Resolve source system code for SalespersonMatcher
        if (sourceSystemId != null) {
            List<Source_System__c> ss = [
                SELECT Code__c FROM Source_System__c WHERE Id = :sourceSystemId LIMIT 1
            ];
            sourceSystemCode = ss.isEmpty() ? null : ss[0].Code__c;
        }

        String q = 'SELECT Id, Status__c, External_Key__c, '
                 + '  Raw_Advertiser_Name__c, Raw_Advertiser_Code__c, '
                 + '  Raw_Salesperson_Code__c, Advertiser_Name__c, '
                 + '  Revenue_Amount__c, Revenue_Type__c, '
                 + '  Period_Month__c, Period_Year__c, '
                 + '  Station_Code__c, Outlet_Code__c, Broadcast_Period__c, '
                 + '  Source_System__c, Load_Batch__c, '
                 + '  Account__c, AE_User__c, '
                 + '  Match_Account_Tier__c, Match_AE_Tier__c, '
                 + '  Excluding_Rule__c '
                 + 'FROM Inbound_Staging__c '
                 + 'WHERE Status__c = \'Pending\'';

        if (sourceSystemId != null) {
            q += ' AND Source_System__c = \'' + String.escapeSingleQuotes(sourceSystemId) + '\'';
        }
        if (loadBatchId != null) {
            q += ' AND Load_Batch__c = \'' + String.escapeSingleQuotes(loadBatchId) + '\'';
        }
        q += ' ORDER BY CreatedDate ASC';
        return Database.getQueryLocator(q);
    }

    public void execute(Database.BatchableContext bc, List<Inbound_Staging__c> scope) {
        ReconciliationEngine.ReconcileResult chunkResult =
            ReconciliationEngine.reconcileBatch(scope, sourceSystemCode);

        totalMatched   += chunkResult.matched;
        totalUnmatched += chunkResult.unmatched;
        totalExcluded  += chunkResult.excluded;
        totalErrors    += chunkResult.errors;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'ReconciliationBatch complete'
            + ' — matched: '   + totalMatched
            + ', unmatched: '  + totalUnmatched
            + ', excluded: '   + totalExcluded
            + ', errors: '     + totalErrors);
    }
}
