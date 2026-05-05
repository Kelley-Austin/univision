@IsTest
private class IngestServiceTest {

    @TestSetup
    static void setup() {
        Source_System__c ss = new Source_System__c(
            Name = 'WideOrbit TV',
            Code__c = 'WIDEORBIT_TV',
            Source_Code__c = 'WIDEORBIT_TV',
            Transformer_Class__c = 'WideOrbitTransformer',
            Is_Active__c = true
        );
        insert ss;
    }

    private static Source_System__c getSource() {
        return [SELECT Id, Code__c FROM Source_System__c WHERE Code__c = 'WIDEORBIT_TV' LIMIT 1];
    }

    private static Id insertContentVersion(String content, String title) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title,
            VersionData = Blob.valueOf(content),
            IsMajorVersion = true
        );
        insert cv;
        return cv.Id;
    }

    private static final String HAPPY_TSV =
        'Advertiser_Name\tAgency_Name\tAccount_Executive\tAir_Date\tGross_Amount\tSpot_Type_Code\tStation\n' +
        'Procter & Gamble\tMindshare\tSMITH_J\t01/15/2025\t50000\t15\tKMEX\n' +
        'Coca-Cola\tMcCann\tJONES_M\t01/20/2025\t25000\t15\tKUVN\n';

    private static final String EMPTY_TSV =
        'Advertiser_Name\tAgency_Name\tAccount_Executive\tAir_Date\tGross_Amount\tSpot_Type_Code\tStation\n';

    private static final String MALFORMED_TSV =
        'Advertiser_Name\tAgency_Name\tAccount_Executive\n' +
        'Procter & Gamble\tMindshare\n';

    @IsTest
    static void happyPath_threeDataRows_pendingAndComplete() {
        Source_System__c ss = getSource();
        Id cvId = insertContentVersion(HAPPY_TSV, 'happy.tsv');

        Test.startTest();
        new IngestService().processUpload(cvId, ss.Id);
        Test.stopTest();

        List<Inbound_Staging__c> rows = [SELECT Status__c FROM Inbound_Staging__c WHERE Source_System__c = :ss.Id];
        System.assertEquals(2, rows.size(), 'Expected 2 staging rows');
        for (Inbound_Staging__c r : rows) {
            System.assertEquals('Pending', r.Status__c);
        }
        Load_Batch__c batch = [SELECT Status__c, Row_Count__c, Error_Count__c FROM Load_Batch__c LIMIT 1];
        System.assertEquals('Complete', batch.Status__c);
        System.assertEquals(2, batch.Row_Count__c);
        System.assertEquals(0, batch.Error_Count__c);
    }

    @IsTest
    static void emptyFile_zeroBatchRowCountComplete() {
        Source_System__c ss = getSource();
        Id cvId = insertContentVersion(EMPTY_TSV, 'empty.tsv');

        Test.startTest();
        new IngestService().processUpload(cvId, ss.Id);
        Test.stopTest();

        Load_Batch__c batch = [SELECT Status__c, Row_Count__c FROM Load_Batch__c LIMIT 1];
        System.assertEquals('Complete', batch.Status__c);
        System.assertEquals(0, batch.Row_Count__c);
        System.assertEquals(0, [SELECT COUNT() FROM Inbound_Staging__c]);
    }

    @IsTest
    static void malformedRow_errorStatusRow() {
        Source_System__c ss = getSource();
        Id cvId = insertContentVersion(MALFORMED_TSV, 'malformed.tsv');

        Test.startTest();
        new IngestService().processUpload(cvId, ss.Id);
        Test.stopTest();

        List<Inbound_Staging__c> rows = [SELECT Status__c, Excluding_Rule__c FROM Inbound_Staging__c];
        System.assertEquals(1, rows.size());
        System.assertEquals('Error', rows[0].Status__c);
    }

    @IsTest
    static void idempotency_sameFileTwice_noNewRecords() {
        Source_System__c ss = getSource();
        Id cvId1 = insertContentVersion(HAPPY_TSV, 'idempotent_1.tsv');
        Id cvId2 = insertContentVersion(HAPPY_TSV, 'idempotent_2.tsv');

        Test.startTest();
        new IngestService().processUpload(cvId1, ss.Id);
        new IngestService().processUpload(cvId2, ss.Id);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Inbound_Staging__c WHERE Source_System__c = :ss.Id];
        System.assertEquals(2, count, 'Upsert on Staging_Key__c should prevent duplicates');
    }

    @IsTest
    static void bomStripping_fileWithBom_processedCorrectly() {
        Source_System__c ss = getSource();
        String bomContent = '﻿' + HAPPY_TSV;
        Id cvId = insertContentVersion(bomContent, 'bom.tsv');

        Test.startTest();
        new IngestService().processUpload(cvId, ss.Id);
        Test.stopTest();

        System.assert([SELECT COUNT() FROM Inbound_Staging__c] > 0, 'BOM stripped file should produce rows');
    }

    @IsTest
    static void stagingKeyComputation_deterministic() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Period_Year__c = 2025,
            Period_Month__c = 1,
            Raw_Advertiser_Name__c = 'Test Corp',
            Revenue_Type__c = 'Linear TV',
            Calendar_Type__c = 'Calendar',
            Unit_Code__c = null
        );
        String key1 = IngestService.computeStagingKey('WIDEORBIT_TV', row);
        String key2 = IngestService.computeStagingKey('WIDEORBIT_TV', row);
        System.assertEquals(key1, key2, 'Staging key must be deterministic');
        System.assertEquals(32, key1.length(), 'MD5 hex should be 32 chars');
    }
}
