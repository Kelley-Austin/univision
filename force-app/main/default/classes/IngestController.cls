/**
 * AuraEnabled controller for the sourceFileUpload, mappingRuleEditor,
 * and loadBatchDashboard LWC components.
 */
public with sharing class IngestController {

    // ── Source System helpers ─────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Source_System__c> getActiveSources() {
        return [
            SELECT Id, Name, Source_Code__c, Transformer_Class__c,
                   File_Encoding__c, Is_Active__c, Last_Load_Date__c, Description__c
            FROM Source_System__c
            WHERE Is_Active__c = true
            ORDER BY Name ASC
        ];
    }

    // ── File upload ───────────────────────────────────────────────────────

    /**
     * Called by sourceFileUpload after the LWC uploads a file via the
     * standard file upload component (which returns a contentDocumentId).
     */
    @AuraEnabled
    public static IngestService.IngestResult processUpload(Id contentDocumentId, Id sourceSystemId) {
        return IngestService.ingest(contentDocumentId, sourceSystemId, false);
    }

    // ── Mapping Rule Editor ───────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Mapping_Rule__c> getMappingRules(Id sourceSystemId) {
        return [
            SELECT Id, Name, Source_Field__c, Target_Field__c,
                   Transform_Logic__c, Default_Value__c, Is_Active__c, Sort_Order__c
            FROM Mapping_Rule__c
            WHERE Source_System__c = :sourceSystemId
              AND Is_Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST, Name ASC
        ];
    }

    @AuraEnabled
    public static void saveMappingRule(Mapping_Rule__c rule) {
        upsert rule;
    }

    @AuraEnabled
    public static void deleteMappingRule(Id ruleId) {
        delete new Mapping_Rule__c(Id = ruleId);
    }

    /**
     * Dry-run: upload a file and return preview rows WITHOUT persisting to Inbound_Staging__c.
     */
    @AuraEnabled
    public static IngestService.IngestResult dryRun(Id contentDocumentId, Id sourceSystemId) {
        return IngestService.ingest(contentDocumentId, sourceSystemId, true);
    }

    // ── Load Batch Dashboard ──────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<BatchStat> getBatchStats() {
        List<BatchStat> stats = new List<BatchStat>();
        for (AggregateResult ar : [
            SELECT Source_System__r.Name sourceName,
                   Status__c status,
                   COUNT(Id) rowCount
            FROM Inbound_Staging__c
            GROUP BY Source_System__r.Name, Status__c
            ORDER BY Source_System__r.Name ASC
        ]) {
            stats.add(new BatchStat(
                (String) ar.get('sourceName'),
                (String) ar.get('status'),
                (Integer) ar.get('rowCount')
            ));
        }
        return stats;
    }

    @AuraEnabled
    public static Id launchBatch(Id sourceSystemId) {
        return Database.executeBatch(new IngestBatch(sourceSystemId), 200);
    }

    public class BatchStat {
        @AuraEnabled public String sourceName { get; set; }
        @AuraEnabled public String status     { get; set; }
        @AuraEnabled public Integer rowCount  { get; set; }

        public BatchStat(String name, String status, Integer count) {
            this.sourceName = name;
            this.status     = status;
            this.rowCount   = count;
        }
    }
}
