@IsTest
private class WideOrbitTransformerTest {

    @TestSetup
    static void setup() {
        TransformerTestHelper.makeSource('WIDEORBIT', 'WideOrbitTransformer', 'UTF-16');
    }

    private static Source_System__c getSource() {
        return [SELECT Id, Source_Code__c FROM Source_System__c WHERE Source_Code__c = 'WIDEORBIT' LIMIT 1];
    }

    @IsTest
    static void happyPath_parsesRowsAndDerivesRevenueType() {
        Source_System__c ss = getSource();
        // Build UTF-8 fixture (decodeUtf16 in unit test context — we test the full flow with tab-delimited content)
        String csv = TransformerTestHelper.wideOrbitCsvHappyPath();
        Blob fileBlob = Blob.valueOf(csv);

        Test.startTest();
        WideOrbitTransformer t = new WideOrbitTransformer();
        List<Inbound_Staging__c> rows = t.transform(fileBlob, ss.Id, false);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'Expect 2 data rows');
        System.assertEquals('Pending', rows[0].Status__c);
        System.assertEquals('Local', rows[0].Revenue_Type__c, 'Local order type should map to Local');
        System.assertEquals('National', rows[1].Revenue_Type__c, 'National order type should map to National');
        System.assertEquals('Acme Corp', rows[0].Advertiser_Name__c);
        System.assertEquals('JD001', rows[0].AE_Code__c);
        System.assertNotEquals(null, rows[0].External_Key__c);
        System.assertNotEquals(rows[0].External_Key__c, rows[1].External_Key__c, 'External keys must be unique per row');
    }

    @IsTest
    static void emptyFile_returnsEmptyList() {
        Source_System__c ss = getSource();
        Test.startTest();
        WideOrbitTransformer t = new WideOrbitTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(''), ss.Id, false);
        Test.stopTest();
        System.assertEquals(0, rows.size(), 'Empty file should produce no rows');
    }

    @IsTest
    static void malformedRow_isExcluded() {
        Source_System__c ss = getSource();
        // Row has fewer columns than header
        String csv = 'advertiser_name\tagency_name\tstation\torder_type\tnet_revenue\tae_code\tbroadcast_period\n'
                   + 'OnlyOneCol\n';
        Test.startTest();
        WideOrbitTransformer t = new WideOrbitTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals(1, rows.size());
        System.assertEquals('Excluded', rows[0].Status__c);
        System.assertEquals('MALFORMED_ROW', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void blankAdvertiser_isExcluded() {
        Source_System__c ss = getSource();
        String csv = 'advertiser_name\tagency_name\tstation\torder_type\tnet_revenue\tae_code\tbroadcast_period\n'
                   + '\tMediaCom\tKTVW\tLocal\t100\tJD\t2026-03\n';
        Test.startTest();
        WideOrbitTransformer t = new WideOrbitTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals(1, rows.size());
        System.assertEquals('Excluded', rows[0].Status__c);
        System.assertEquals('BLANK_ADVERTISER', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void idempotency_sameRowProducesSameExternalKey() {
        Source_System__c ss = getSource();
        String csv = TransformerTestHelper.wideOrbitCsvHappyPath();
        WideOrbitTransformer t = new WideOrbitTransformer();

        Test.startTest();
        List<Inbound_Staging__c> rows1 = t.transform(Blob.valueOf(csv), ss.Id, false);
        List<Inbound_Staging__c> rows2 = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();

        System.assertEquals(rows1[0].External_Key__c, rows2[0].External_Key__c,
            'Same input must always produce the same External_Key__c');
    }

    @IsTest
    static void digitalOrderType_mapsToDigital() {
        Source_System__c ss = getSource();
        String csv = 'advertiser_name\tagency_name\tstation\torder_type\tnet_revenue\tae_code\tbroadcast_period\n'
                   + 'Digital Co\tAgency\tKTVW\tDigital\t5000\tAA\t2026-03\n';
        WideOrbitTransformer t = new WideOrbitTransformer();
        Test.startTest();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals('Digital', rows[0].Revenue_Type__c);
    }

    @IsTest
    static void dryRun_doesNotPersist() {
        Source_System__c ss = getSource();
        String csv = TransformerTestHelper.wideOrbitCsvHappyPath();
        WideOrbitTransformer t = new WideOrbitTransformer();
        Test.startTest();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, true);
        Test.stopTest();
        System.assertEquals(2, rows.size(), 'Dry run should still return rows');
        System.assertEquals(0, [SELECT COUNT() FROM Inbound_Staging__c], 'Dry run must not insert records');
    }
}
