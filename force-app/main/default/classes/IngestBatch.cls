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
    private String jobId;

    public IngestBatch(Id sourceSystemId) {
        this.sourceSystemId = sourceSystemId;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.jobId = bc.getJobId();
        String query = 'SELECT Id, External_Key__c, Status__c, Advertiser_Name__c, '
                     + 'Agency_Name__c, Station_Code__c, Revenue_Type__c, Revenue_Amount__c, '
                     + 'AE_Code__c, Broadcast_Period__c, Source_System__c, Batch_Job_Id__c '
                     + 'FROM Inbound_Staging__c '
                     + 'WHERE Status__c = \'Pending\'';
        if (sourceSystemId != null) {
            query += ' AND Source_System__c = \'' + String.escapeSingleQuotes(sourceSystemId) + '\'';
        }
        query += ' ORDER BY CreatedDate ASC';
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Inbound_Staging__c> scope) {
        // Stamp batch job ID for traceability; keep status Pending during processing
        for (Inbound_Staging__c row : scope) {
            row.Batch_Job_Id__c = bc.getJobId();
        }
        update scope;

        List<Inbound_Staging__c> toUpdate = new List<Inbound_Staging__c>();

        for (Inbound_Staging__c row : scope) {
            processed++;
            try {
                // Resolve advertiser Account
                Id advertiserId = resolveAccount(row.Advertiser_Name__c, 'Advertiser');
                if (advertiserId == null) {
                    row.Status__c = 'Excluded';
                    row.Excluding_Rule__c = 'UNKNOWN_ADVERTISER';
                    toUpdate.add(row);
                    continue;
                }

                // Promote to Actual_Revenue__c (canonical record)
                Actual_Revenue__c actual = buildActual(row, advertiserId);
                upsert actual External_Key__c;

                row.Status__c = 'Matched';
                promoted++;
            } catch (Exception ex) {
                row.Status__c = 'Error';
                row.Excluding_Rule__c = ex.getMessage().abbreviate(255);
                errors++;
            }
            toUpdate.add(row);
        }

        update toUpdate;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'IngestBatch complete — processed: ' + processed
            + ', promoted: ' + promoted
            + ', errors: ' + errors);
    }

    // ── Private helpers ───────────────────────────────────────────────────

    private static Map<String, Id> accountCache = new Map<String, Id>();

    private static Id resolveAccount(String name, String recordTypeName) {
        if (String.isBlank(name)) return null;
        String key = (name + '|' + recordTypeName).toLowerCase();
        if (accountCache.containsKey(key)) return accountCache.get(key);

        List<Account> matches = [
            SELECT Id FROM Account
            WHERE Name = :name
              AND RecordType.DeveloperName = :recordTypeName
            LIMIT 1
        ];
        Id result = matches.isEmpty() ? null : matches[0].Id;
        accountCache.put(key, result);
        return result;
    }

    private static Actual_Revenue__c buildActual(Inbound_Staging__c row, Id advertiserId) {
        Actual_Revenue__c a = new Actual_Revenue__c();
        a.External_Key__c    = row.External_Key__c;
        a.Advertiser__c      = advertiserId;
        a.Revenue_Amount__c  = row.Revenue_Amount__c;
        a.Revenue_Type__c    = row.Revenue_Type__c;
        a.Station_Code__c    = row.Station_Code__c;
        a.AE_Code__c         = row.AE_Code__c;
        a.Broadcast_Period__c = row.Broadcast_Period__c;
        a.Source_System__c   = row.Source_System__c;
        a.Inbound_Staging__c = row.Id;
        return a;
    }
}
