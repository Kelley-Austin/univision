@IsTest
private class IngestServiceTest {

    @TestSetup
    static void setup() {
        TransformerTestHelper.makeSource('STRATA', 'StrataTransformer', 'UTF-8');
    }

    private static Source_System__c getSource() {
        return [SELECT Id, Source_Code__c FROM Source_System__c WHERE Source_Code__c = 'STRATA' LIMIT 1];
    }

    private static Id insertContentDocument(String csvContent) {
        ContentVersion cv = new ContentVersion(
            Title        = 'test_strata.csv',
            PathOnClient = 'test_strata.csv',
            VersionData  = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    @IsTest
    static void ingest_happyPath_createsStagingRows() {
        Source_System__c ss = getSource();
        String csv = 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
                   + 'abc-111-222-333-444556789012,Acme Corp,Agency,KTVW,Local,5000,AE,2026-03\n';
        Id cdId = insertContentDocument(csv);

        Test.startTest();
        IngestService.IngestResult result = IngestService.ingest(cdId, ss.Id, false);
        Test.stopTest();

        System.assertEquals(1, result.totalRows);
        System.assertEquals(1, result.pendingRows);
        System.assertEquals(0, result.excludedRows);
        System.assert(result.errors.isEmpty(), 'No errors expected');
        System.assertEquals(1, [SELECT COUNT() FROM Inbound_Staging__c], 'One staging row should be persisted');
    }

    @IsTest
    static void ingest_dryRun_doesNotPersist() {
        Source_System__c ss = getSource();
        String csv = 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
                   + 'abc-111-222-333-444556789012,Acme Corp,Agency,KTVW,Local,5000,AE,2026-03\n';
        Id cdId = insertContentDocument(csv);

        Test.startTest();
        IngestService.IngestResult result = IngestService.ingest(cdId, ss.Id, true);
        Test.stopTest();

        System.assertEquals(1, result.totalRows);
        System.assert(result.dryRun, 'Should be flagged as dry run');
        System.assertEquals(0, [SELECT COUNT() FROM Inbound_Staging__c], 'Dry run must not persist');
    }

    @IsTest
    static void ingest_inactiveSource_throwsException() {
        Source_System__c ss = getSource();
        ss.Is_Active__c = false;
        update ss;
        Id cdId = insertContentDocument('dummy');

        Test.startTest();
        try {
            IngestService.ingest(cdId, ss.Id, false);
            System.assert(false, 'Expected exception');
        } catch (IngestService.IngestException ex) {
            System.assert(ex.getMessage().contains('not found or inactive'), ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void ingest_missingContentDocument_throwsException() {
        Source_System__c ss = getSource();
        Id fakeDocId = '069000000000001AAA'; // well-formed fake Id

        Test.startTest();
        try {
            IngestService.ingest(fakeDocId, ss.Id, false);
            System.assert(false, 'Expected exception');
        } catch (IngestService.IngestException ex) {
            System.assert(ex.getMessage().contains('no latest version'), ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void ingestBlob_happyPath_createsRows() {
        Source_System__c ss = getSource();
        String csv = 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
                   + 'blob-guid-111-222-333-444556,Blob Corp,Agency,KTVW,Local,9000,AE,2026-04\n';

        Test.startTest();
        IngestService.IngestResult result = IngestService.ingestBlob(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();

        System.assertEquals(1, result.totalRows);
        System.assertEquals(1, [SELECT COUNT() FROM Inbound_Staging__c]);
    }

    @IsTest
    static void ingest_emptyFile_returnsZeroRows() {
        Source_System__c ss = getSource();
        Id cdId = insertContentDocument('');

        Test.startTest();
        IngestService.IngestResult result = IngestService.ingest(cdId, ss.Id, false);
        Test.stopTest();

        System.assertEquals(0, result.totalRows);
        System.assertEquals(0, [SELECT COUNT() FROM Inbound_Staging__c]);
    }

    @IsTest
    static void ingest_idempotency_upsertDoesNotDuplicate() {
        Source_System__c ss = getSource();
        String csv = 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
                   + 'idem-guid-111-222-333-4445567,Idempotent Corp,Agency,KTVW,Local,1000,AE,2026-03\n';

        Test.startTest();
        IngestService.ingestBlob(Blob.valueOf(csv), ss.Id, false);
        IngestService.ingestBlob(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Inbound_Staging__c], 'Upsert must prevent duplicates');
    }
}
