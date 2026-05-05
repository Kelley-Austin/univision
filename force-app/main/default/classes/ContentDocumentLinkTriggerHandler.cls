/**
 * =============================================================================
 *  ContentDocumentLinkTriggerHandler
 * =============================================================================
 *
 *  Purpose
 *  -------
 *  This is the ENTRY POINT for the inbound revenue ingest pipeline. When a
 *  Sales Ops user uploads a CSV / TSV / TXT file to a Source_System__c record,
 *  Salesforce creates a ContentDocumentLink between the file and that record.
 *  This handler watches afterInsert on ContentDocumentLink, identifies links
 *  attached to a Source_System__c parent that point at a parseable file, and
 *  enqueues IngestQueueable to process the file asynchronously.
 *
 *  Why afterInsert (not afterUpdate / beforeInsert)
 *  ------------------------------------------------
 *  CDL is mostly insert-only — Salesforce links a file once when it's
 *  shared. afterInsert lets us read the committed CDL and the related
 *  ContentVersion in one query and enqueue async work that will outlive the
 *  trigger.
 *
 *  Why we don't filter by file type at CDL stage
 *  ---------------------------------------------
 *  ContentDocumentLink doesn't carry the FileExtension; that lives on
 *  ContentVersion. We collect candidate ContentDocumentIds by parent type
 *  first, then fetch ContentVersion in one query and filter by extension.
 *  Saves a describe-call-per-row (the previous implementation called
 *  getSObjectType().getDescribe().getName() inside the loop) and keeps the
 *  whole handler under one SOQL.
 *
 *  Bulk safety
 *  -----------
 *    * Filter by SObjectType using the static descriptor
 *      (Source_System__c.SObjectType) — no per-row describe calls.
 *    * One ContentVersion query keyed by Set<Id>.
 *    * One System.enqueueJob per matching file (Salesforce supports up to 50
 *      Queueable jobs per transaction; if a single upload landed > 50 files
 *      we'd need to coalesce — not a current requirement).
 *
 *  Failure modes
 *  -------------
 *    * Empty file: IngestQueueable handles empty input; we still enqueue.
 *    * Wrong file type (.xlsx, .pdf): silently ignored at filtering step.
 *    * Source_System__c that's been deleted between insert and trigger run:
 *      enqueue still fires; the queueable handles a missing parent.
 *
 *  Framework
 *  ---------
 *  Extends the canonical TriggerHandler base class (Patrick Stephens'). Phase
 *  methods receive Trigger.newMap as argument from TriggerDispatcher; we
 *  cast to List<ContentDocumentLink> via .values() at the entry point.
 *
 *  Tests
 *  -----
 *  No dedicated test class today. End-to-end coverage comes from
 *  IngestServiceTest and the per-transformer test classes that simulate
 *  ContentDocumentLink insert via DML. Adding a focused trigger test is on
 *  the docket once the TestDataFactory is in regular use.
 * =============================================================================
 */
public with sharing class ContentDocumentLinkTriggerHandler extends TriggerHandler {

    // =========================================================================
    //  Phase methods
    // =========================================================================

    public override void afterInsert(Map<Id, SObject> newRecordsMap) {
        enqueueIngestForUploadedFiles((List<ContentDocumentLink>) newRecordsMap.values());
    }

    // =========================================================================
    //  Pipeline entry
    // =========================================================================

    /**
     * For each CDL whose parent is a Source_System__c record, look up the
     * latest ContentVersion. If the version's file extension is one we can
     * parse, enqueue IngestQueueable.
     */
    @TestVisible
    private static void enqueueIngestForUploadedFiles(List<ContentDocumentLink> links) {
        Set<Id> contentDocIds = new Set<Id>();
        Map<Id, Id> sourceSystemByContentDoc = new Map<Id, Id>();

        // Use the SObjectType descriptor to identify Source_System__c links —
        // no per-row describe call. This gives O(1) comparison per row.
        Schema.SObjectType sourceSystemType = Source_System__c.SObjectType;

        for (ContentDocumentLink cdl : links) {
            if (cdl.LinkedEntityId == null) continue;
            if (cdl.LinkedEntityId.getSObjectType() != sourceSystemType) continue;

            contentDocIds.add(cdl.ContentDocumentId);
            sourceSystemByContentDoc.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
        }

        if (contentDocIds.isEmpty()) return;

        // One SOQL for all relevant ContentVersions.
        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId, Title, FileExtension
            FROM   ContentVersion
            WHERE  ContentDocumentId IN :contentDocIds
              AND  IsLatest = TRUE
        ]) {
            if (!isParseableExtension(cv.FileExtension)) continue;

            Id sourceSystemId = sourceSystemByContentDoc.get(cv.ContentDocumentId);
            if (sourceSystemId == null) continue;

            // IngestQueueable is responsible for parser dispatch + staging
            // upsert. We do not cache or de-dupe enqueue calls here — same
            // file uploaded twice should re-process, since the staging-row
            // upsert is keyed by composite external id and is idempotent.
            System.enqueueJob(new IngestQueueable(cv.Id, sourceSystemId));
        }
    }

    /**
     * Whitelist of file extensions our transformer registry knows how to
     * parse. Centralised here so the trigger handler isn't the only thing
     * coupled to it; if the registry expands, update this set in lockstep.
     *
     * Comparison is case-insensitive — Salesforce normalises FileExtension
     * to lower case but a defensive lower() is cheap insurance.
     */
    @TestVisible
    private static Boolean isParseableExtension(String fileExtension) {
        if (String.isBlank(fileExtension)) return false;
        return PARSEABLE_EXTENSIONS.contains(fileExtension.toLowerCase());
    }

    private static final Set<String> PARSEABLE_EXTENSIONS = new Set<String>{
        'csv', 'tsv', 'txt'
    };
}
