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
        Load_Batch__c batch = new Load_Batch__c(
            Source_System__c = ss.Id,
            File_Name__c = cv.Title,
            Status__c = 'Processing',
            Content_Version_Id__c = cv.Id
        );
        insert batch;

        List<Inbound_Staging__c> stagingRows;
        try {
            stagingRows = transformer.transform(fileContent, batch.Id, ss.Id, ss.Code__c);
        } catch (Exception e) {
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
            if (!upsertResults[i].isSuccess()) {
                upsertErrors++;
                for (Database.Error err : upsertResults[i].getErrors()) {
                    errorMsgs.add(err.getMessage());
                }
            }
        }

        batch.Row_Count__c  = stagingRows.size();
        batch.Error_Count__c = upsertErrors;
        batch.Processed_At__c = Datetime.now();
        batch.Status__c = upsertErrors == 0 ? 'Complete'
                        : upsertErrors < stagingRows.size() ? 'Partial'
                        : 'Failed';
        update batch;
        updateSourceSystemTimestamp(ss.Id);

        IngestResult result = countResult(stagingRows, false);
        result.errorCount += upsertErrors;
        result.errors = errorMsgs;
        return result;
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
