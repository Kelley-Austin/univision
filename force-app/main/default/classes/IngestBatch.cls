/**
 * Batch class that promotes Pending Inbound_Staging__c rows to Actual_Revenue__c records.
 * Run via: Database.executeBatch(new IngestBatch(sourceSystemId), 200);
 * Or schedule nightly via scheduled Apex.
 */
public with sharing class IngestBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Id sourceSystemId;
    private Integer processed = 0;
    private Integer promoted  = 0;
    private Integer errors    = 0;

    public IngestBatch(Id sourceSystemId) {
        this.sourceSystemId = sourceSystemId;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, Staging_Key__c, Status__c, '
                     + 'Raw_Advertiser_Name__c, Raw_Agency_Name__c, Outlet_Code__c, '
                     + 'Revenue_Type__c, Revenue_Amount__c, Raw_Salesperson_Code__c, '
                     + 'Period_Month__c, Period_Year__c, Calendar_Type__c, '
                     + 'Source_System__c, Load_Batch__c, Account__c, Batch_Job_Id__c '
                     + 'FROM Inbound_Staging__c '
                     + 'WHERE Status__c = \'Pending\'';
        if (sourceSystemId != null) {
            query += ' AND Source_System__c = \'' + String.escapeSingleQuotes(sourceSystemId) + '\'';
        }
        query += ' ORDER BY CreatedDate ASC';
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Inbound_Staging__c> scope) {
        // Stamp batch job ID for traceability
        for (Inbound_Staging__c row : scope) {
            row.Batch_Job_Id__c = bc.getJobId();
        }
        update scope;

        // Collect all unique names not yet in the static cache, then bulk-query once
        Set<String> uncachedNames = new Set<String>();
        for (Inbound_Staging__c row : scope) {
            if (row.Account__c == null && String.isNotBlank(row.Raw_Advertiser_Name__c)) {
                String key = row.Raw_Advertiser_Name__c.toLowerCase();
                if (!accountCache.containsKey(key)) uncachedNames.add(row.Raw_Advertiser_Name__c);
            }
        }
        if (!uncachedNames.isEmpty()) {
            for (Account a : [
                SELECT Id, Name FROM Account
                WHERE Name IN :uncachedNames
                  AND RecordType.DeveloperName IN ('Direct_Buy', 'Advertiser')
            ]) {
                accountCache.put(a.Name.toLowerCase(), a.Id);
            }
            // Mark all names queried but not found as null so we don't re-query them
            for (String name : uncachedNames) {
                if (!accountCache.containsKey(name.toLowerCase())) {
                    accountCache.put(name.toLowerCase(), null);
                }
            }
        }

        List<Actual_Revenue__c> actualsToUpsert = new List<Actual_Revenue__c>();
        List<Integer> actualIndexes = new List<Integer>();
        List<Inbound_Staging__c> toUpdate = new List<Inbound_Staging__c>();

        for (Inbound_Staging__c row : scope) {
            processed++;
            Id advertiserId = row.Account__c;
            if (advertiserId == null && String.isNotBlank(row.Raw_Advertiser_Name__c)) {
                advertiserId = accountCache.get(row.Raw_Advertiser_Name__c.toLowerCase());
            }
            if (advertiserId == null) {
                row.Status__c = 'Excluded';
                row.Excluding_Rule__c = 'UNKNOWN_ADVERTISER';
                toUpdate.add(row);
                continue;
            }
            row.Status__c = 'Matched';
            promoted++;
            toUpdate.add(row);
            actualsToUpsert.add(buildActual(row, advertiserId));
            actualIndexes.add(toUpdate.size() - 1);
        }

        // Bulk upsert all actuals (one DML per execute chunk)
        if (!actualsToUpsert.isEmpty()) {
            Database.UpsertResult[] uResults =
                Database.upsert(actualsToUpsert, Actual_Revenue__c.External_Key__c, false);
            for (Integer i = 0; i < uResults.size(); i++) {
                if (!uResults[i].isSuccess()) {
                    Inbound_Staging__c failedRow = toUpdate[actualIndexes[i]];
                    failedRow.Status__c = 'Error';
                    failedRow.Excluding_Rule__c =
                        uResults[i].getErrors()[0].getMessage().abbreviate(255);
                    errors++;
                    promoted--;
                }
            }
        }

        update toUpdate;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'IngestBatch complete — processed: ' + processed
            + ', promoted: ' + promoted
            + ', errors: ' + errors);

        // Emit promotion-complete event. Sourced by Sales Ops dashboards
        // (filter LogEventName starts-with 'Ingest.' or 'IngestBatch.').
        // EventKey is the sourceSystemId (or 'ALL' if scoped to all sources)
        // so the panel can group by source. CorrelationId from the BatchableContext
        // jobId so all chunks of one batch share an ID.
        String sourceKey = sourceSystemId != null ? String.valueOf(sourceSystemId) : 'ALL';
        String type = errors == 0 ? 'Info' : (errors < processed ? 'Warning' : 'Error');
        String eventName = errors == 0
            ? 'IngestBatch.PromoteCompleted'
            : (errors < processed ? 'IngestBatch.PromotePartial' : 'IngestBatch.PromoteFailed');

        Log batchLog = new Log(
            eventName,
            type,
            'IngestBatch promote: processed=' + processed
                + ' promoted=' + promoted + ' errors=' + errors,
            sourceKey,
            JSON.serialize(new Map<String, Object>{
                'jobId'          => bc.getJobId(),
                'sourceSystemId' => sourceSystemId,
                'processed'      => processed,
                'promoted'       => promoted,
                'errors'         => errors
            }),
            String.valueOf(bc.getJobId())
        );
        batchLog.emit();
    }

    // ── Private helpers ───────────────────────────────────────────────────

    // Static cache persists across execute() calls within the same batch job (Database.Stateful)
    private static Map<String, Id> accountCache = new Map<String, Id>();

    @TestVisible
    private static Actual_Revenue__c buildActual(Inbound_Staging__c row, Id advertiserId) {
        Actual_Revenue__c a = new Actual_Revenue__c();
        // Staging_Key__c is the MD5 idempotency hash set by IngestService — reuse it
        // as the External_Key__c on Actual_Revenue__c so re-runs are safe
        a.External_Key__c    = row.Staging_Key__c;
        a.Advertiser__c      = advertiserId;
        a.Revenue_Amount__c  = row.Revenue_Amount__c;
        a.Revenue_Type__c    = row.Revenue_Type__c;
        a.Station_Code__c    = row.Outlet_Code__c;
        a.Period_Month__c    = row.Period_Month__c;
        a.Period_Year__c     = row.Period_Year__c;
        a.Source_System__c   = row.Source_System__c;
        a.Inbound_Staging__c = row.Id;
        return a;
    }
}
