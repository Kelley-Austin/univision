public with sharing class IngestService {

    public class IngestResult {
        @AuraEnabled public Integer totalRows    = 0;
        @AuraEnabled public Integer pendingRows  = 0;
        @AuraEnabled public Integer excludedRows = 0;
        @AuraEnabled public Integer errorCount   = 0;
        @AuraEnabled public Boolean dryRun       = false;
        @AuraEnabled public List<String> errors  = new List<String>();
    }

    // Called from IngestController (LWC direct-upload path).
    // Takes a ContentDocumentId (what lightning-file-upload returns).
    public static IngestResult ingest(Id contentDocumentId, Id sourceSystemId, Boolean isDryRun) {
        ContentVersion cv = [
            SELECT Id, Title, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            LIMIT 1
        ];
        Source_System__c ss = [
            SELECT Id, Code__c, Name FROM Source_System__c WHERE Id = :sourceSystemId LIMIT 1
        ];
        String fileContent = cv.VersionData.toString();
        if (fileContent.startsWith('﻿')) fileContent = fileContent.substring(1);

        SourceSystemTransformer transformer = TransformerRegistry.getTransformer(ss.Code__c);

        if (isDryRun) {
            List<Inbound_Staging__c> rows = transformer.transform(fileContent, null, sourceSystemId, ss.Code__c);
            new MappingRuleExecutor(sourceSystemId).apply(rows);
            return countResult(rows, true);
        }

        return doIngest(cv, ss, fileContent, transformer);
    }

    // Called from IngestQueueable (async file-upload path).
    // Takes a ContentVersionId (what the queueable receives after file upload).
    public void processUpload(Id contentVersionId, Id sourceSystemId) {
        Source_System__c ss = [
            SELECT Id, Code__c, Name FROM Source_System__c WHERE Id = :sourceSystemId LIMIT 1
        ];
        ContentVersion cv = [
            SELECT Id, Title, VersionData FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1
        ];
        String fileContent = cv.VersionData.toString();
        if (fileContent.startsWith('﻿')) fileContent = fileContent.substring(1);
        SourceSystemTransformer transformer = TransformerRegistry.getTransformer(ss.Code__c);
        doIngest(cv, ss, fileContent, transformer);
    }

    private static IngestResult doIngest(
        ContentVersion cv,
        Source_System__c ss,
        String fileContent,
        SourceSystemTransformer transformer
    ) {
        // Per-ingest correlationId so every Log__c entry from this batch
        // (transform failure, per-row upsert failure, top-level exception)
        // shares a single ID. Operators can filter Log__c.CorrelationId__c
        // to see the full failure timeline for one upload.
        String correlationId = LogX.getGuid();

        Load_Batch__c batch = new Load_Batch__c(
            Source_System__c = ss.Id,
            File_Name__c = cv.Title,
            Status__c = 'Processing',
            Content_Version_Id__c = cv.Id
        );
        insert batch;

        Long startMs = Datetime.now().getTime();

        // Emit ingest-started event so the Sales Ops "Last Imported Date" panel
        // and any forensic dashboard can see this run before it completes.
        new Log(
            'Ingest.Started',
            'Info',
            'Ingest started for ' + ss.Code__c + ' file=' + cv.Title,
            ss.Code__c,
            JSON.serialize(new Map<String, Object>{
                'sourceCode'      => ss.Code__c,
                'sourceSystemId'  => ss.Id,
                'sourceName'      => ss.Name,
                'fileName'        => cv.Title,
                'contentVersionId'=> cv.Id,
                'loadBatchId'     => batch.Id
            }),
            correlationId
        ).emit();

        try {
            List<Inbound_Staging__c> stagingRows;
            try {
                stagingRows = transformer.transform(fileContent, batch.Id, ss.Id, ss.Code__c);
            } catch (Exception e) {
                // Transform failure: log the full exception (stack trace, type)
                // BEFORE we wrap-and-rethrow as IngestException. The wrapper
                // exception's message would otherwise be all the caller sees.
                LogX.logException(
                    e,
                    'IngestService.doIngest transform failed (sourceSystem=' + ss.Code__c +
                        ', batch=' + batch.Id + ', file=' + cv.Title + ')',
                    correlationId,
                    /* doEmit */ true
                );
                batch.Status__c = 'Failed';
                batch.Error_Count__c = 1;
                batch.Processed_At__c = Datetime.now();
                update batch;
                throw new IngestException('Transform failed: ' + e.getMessage());
            }

            if (stagingRows == null || stagingRows.isEmpty()) {
                batch.Status__c = 'Complete';
                batch.Row_Count__c = 0;
                batch.Error_Count__c = 0;
                batch.Processed_At__c = Datetime.now();
                update batch;
                updateSourceSystemTimestamp(ss.Id);

                Log emptyLog = new Log(
                    'Ingest.Empty',
                    'Warning',
                    'Ingest produced 0 rows for ' + ss.Code__c + ' file=' + cv.Title,
                    ss.Code__c,
                    JSON.serialize(new Map<String, Object>{
                        'sourceCode'     => ss.Code__c,
                        'sourceSystemId' => ss.Id,
                        'fileName'       => cv.Title,
                        'loadBatchId'    => batch.Id,
                        'rowCount'       => 0,
                        'durationMs'     => Datetime.now().getTime() - startMs
                    }),
                    correlationId
                );
                emptyLog.ObjectReferenceId = batch.Id;
                emptyLog.emit();
                return new IngestResult();
            }

            new MappingRuleExecutor(ss.Id).apply(stagingRows);

            for (Inbound_Staging__c row : stagingRows) {
                row.Staging_Key__c = computeStagingKey(ss.Code__c, row);
            }

            Database.UpsertResult[] upsertResults = Database.upsert(stagingRows, Inbound_Staging__c.Staging_Key__c, false);

            Integer upsertErrors = 0;
            List<String> errorMsgs = new List<String>();
            for (Integer i = 0; i < upsertResults.size(); i++) {
                if (upsertResults[i].isSuccess()) continue;
                upsertErrors++;
                for (Database.Error err : upsertResults[i].getErrors()) {
                    errorMsgs.add(err.getMessage());
                }
                // Emit the full Database.error[] to Log__c. errorMsgs above
                // gives the LWC a quick string list for inline display; the
                // Log__c entries preserve status code, fields, etc. for triage.
                LogX.logErrors(
                    upsertResults[i].getErrors(),
                    'IngestService.doIngest: Inbound_Staging__c upsert failed' +
                        ' (sourceSystem=' + ss.Code__c + ', batch=' + batch.Id + ')',
                    correlationId
                );
            }

            batch.Row_Count__c  = stagingRows.size();
            batch.Error_Count__c = upsertErrors;
            batch.Processed_At__c = Datetime.now();
            batch.Status__c = upsertErrors == 0 ? 'Complete'
                            : upsertErrors < stagingRows.size() ? 'Partial'
                            : 'Failed';
            update batch;
            updateSourceSystemTimestamp(ss.Id);

            // Emit completion event. EventKey is the source system code so the
            // Sales Ops "Last Imported Date" panel can group by EventKey and
            // surface MAX(ComposedDateTime__c) per source.
            String eventName = upsertErrors == 0
                ? 'Ingest.Completed'
                : upsertErrors < stagingRows.size() ? 'Ingest.PartialFailure' : 'Ingest.Failed';
            String logType = upsertErrors == 0 ? 'Info'
                            : upsertErrors < stagingRows.size() ? 'Warning' : 'Error';

            Log completionLog = new Log(
                eventName,
                logType,
                'Ingest ' + batch.Status__c + ' ' + ss.Code__c +
                    ' rows=' + stagingRows.size() + ' errors=' + upsertErrors,
                ss.Code__c,
                JSON.serialize(new Map<String, Object>{
                    'sourceCode'     => ss.Code__c,
                    'sourceSystemId' => ss.Id,
                    'fileName'       => cv.Title,
                    'loadBatchId'    => batch.Id,
                    'rowCount'       => stagingRows.size(),
                    'errorCount'     => upsertErrors,
                    'status'         => batch.Status__c,
                    'durationMs'     => Datetime.now().getTime() - startMs
                }),
                correlationId
            );
            completionLog.ObjectReferenceId = batch.Id;
            completionLog.emit();

            IngestResult result = countResult(stagingRows, false);
            result.errorCount += upsertErrors;
            result.errors = errorMsgs;
            return result;

        } catch (Exception ex) {
            // Top-level: catch anything the inner blocks didn't (DML failures,
            // mapping-rule executor errors, etc.) so the failure leaves a
            // Log__c entry even though we rethrow. doEmit=true uses the
            // platform-event path so the entry survives any rollback caused
            // by the rethrow. IngestException re-emerges from the inner
            // catch and is logged here as well — slight duplication, worth it
            // for top-level safety net coverage.
            if (!(ex instanceof IngestException)) {
                // The transform-failure path already logged its own exception
                // before wrapping. Anything ELSE is a path we haven't logged
                // yet; capture it now.
                LogX.logException(
                    ex,
                    'IngestService.doIngest unexpected failure (sourceSystem=' + ss.Code__c +
                        ', batch=' + batch.Id + ')',
                    correlationId,
                    /* doEmit */ true
                );
            }
            throw ex;
        }
    }

    private static IngestResult countResult(List<Inbound_Staging__c> rows, Boolean dryRun) {
        IngestResult res = new IngestResult();
        res.dryRun = dryRun;
        res.totalRows = rows.size();
        for (Inbound_Staging__c r : rows) {
            if (r.Status__c == 'Pending')  res.pendingRows++;
            else if (r.Status__c == 'Excluded') res.excludedRows++;
            else if (r.Status__c == 'Error')    res.errorCount++;
        }
        return res;
    }

    private static void updateSourceSystemTimestamp(Id sourceSystemId) {
        update new Source_System__c(Id = sourceSystemId, Last_Uploaded_At__c = Datetime.now());
    }

    @TestVisible
    static String computeStagingKey(String ssCode, Inbound_Staging__c row) {
        String raw = String.join(new List<String>{
            ssCode,
            String.valueOf(row.Period_Year__c),
            String.valueOf(row.Period_Month__c),
            String.valueOf(row.Raw_Advertiser_Name__c),
            String.valueOf(row.Revenue_Type__c),
            String.valueOf(row.Calendar_Type__c),
            String.valueOf(row.Unit_Code__c)
        }, '|');
        Blob digest = Crypto.generateDigest('MD5', Blob.valueOf(raw));
        return EncodingUtil.convertToHex(digest);
    }

    public class IngestException extends Exception {}
}
