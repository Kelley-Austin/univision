public with sharing class IngestService {

    public void processUpload(Id contentVersionId, Id sourceSystemId) {
        Source_System__c ss = [
            SELECT Id, Code__c, Name FROM Source_System__c WHERE Id = :sourceSystemId LIMIT 1
        ];

        ContentVersion cv = [
            SELECT Id, Title, VersionData FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1
        ];

        String fileContent = cv.VersionData.toString();
        // Strip UTF-16 BOM if present. Counterpoint CP1252 special chars survive as-is in UTF-8 decode.
        if (fileContent.startsWith('﻿')) {
            fileContent = fileContent.substring(1);
        }

        Load_Batch__c batch = new Load_Batch__c(
            Source_System__c = sourceSystemId,
            File_Name__c = cv.Title,
            Status__c = 'Processing',
            Content_Version_Id__c = contentVersionId
        );
        insert batch;

        List<Inbound_Staging__c> stagingRows;
        try {
            SourceSystemTransformer transformer = TransformerRegistry.getTransformer(ss.Code__c);
            stagingRows = transformer.transform(fileContent, batch.Id, sourceSystemId, ss.Code__c);
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
            updateSourceSystemTimestamp(sourceSystemId);
            return;
        }

        new MappingRuleExecutor(sourceSystemId).apply(stagingRows);

        for (Inbound_Staging__c row : stagingRows) {
            row.Staging_Key__c = computeStagingKey(ss.Code__c, row);
        }

        Database.UpsertResult[] results = Database.upsert(stagingRows, Inbound_Staging__c.Staging_Key__c, false);

        Integer errorCount = 0;
        for (Database.UpsertResult ur : results) {
            if (!ur.isSuccess()) errorCount++;
        }

        batch.Row_Count__c = stagingRows.size();
        batch.Error_Count__c = errorCount;
        batch.Processed_At__c = Datetime.now();
        if (errorCount == 0) {
            batch.Status__c = 'Complete';
        } else if (errorCount < stagingRows.size()) {
            batch.Status__c = 'Partial';
        } else {
            batch.Status__c = 'Failed';
        }
        update batch;
        updateSourceSystemTimestamp(sourceSystemId);
    }

    private void updateSourceSystemTimestamp(Id sourceSystemId) {
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
}
