@IsTest
private class StrataTransformerTest {

    @TestSetup
    static void setup() {
        TransformerTestHelper.makeSource('STRATA', 'StrataTransformer', 'UTF-8');
    }

    private static Source_System__c getSource() {
        return [SELECT Id FROM Source_System__c WHERE Source_Code__c = 'STRATA' LIMIT 1];
    }

    @IsTest
    static void happyPath_excludesNullGuidRows() {
        Source_System__c ss = getSource();
        Blob b = Blob.valueOf(TransformerTestHelper.strataCsvHappyPath());
        Test.startTest();
        StrataTransformer t = new StrataTransformer();
        List<Inbound_Staging__c> rows = t.transform(b, ss.Id, false);
        Test.stopTest();
        System.assertEquals(2, rows.size(), 'Both rows returned (one Pending, one Excluded)');
        System.assertEquals('Pending', rows[0].Status__c);
        System.assertEquals('Excluded', rows[1].Status__c);
        System.assertEquals('NULL_GUID', rows[1].Excluding_Rule__c);
    }

    @IsTest
    static void emptyGuid_isExcluded() {
        Source_System__c ss = getSource();
        String csv = 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
                   + ',Acme Corp,MediaCom,KTVW,Local,1000,AE,2026-03\n';
        StrataTransformer t = new StrataTransformer();
        Test.startTest();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals('NULL_GUID', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void emptyFile_returnsEmpty() {
        Source_System__c ss = getSource();
        Test.startTest();
        StrataTransformer t = new StrataTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(''), ss.Id, false);
        Test.stopTest();
        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void malformedRow_isExcluded() {
        Source_System__c ss = getSource();
        String csv = 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
                   + 'abc-123\n';
        Test.startTest();
        StrataTransformer t = new StrataTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals('MALFORMED_ROW', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void blankAdvertiser_isExcluded() {
        Source_System__c ss = getSource();
        String csv = 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
                   + 'abc-123-valid-guid-here123,,,KTVW,Local,1000,AE,2026-03\n';
        Test.startTest();
        StrataTransformer t = new StrataTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals('BLANK_ADVERTISER', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void idempotency_guidUsedAsFingerprint() {
        Source_System__c ss = getSource();
        String csv = 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
                   + 'abc-123-def-456-789012345678,Acme Corp,Agency,KTVW,Local,1000,AE,2026-03\n';
        StrataTransformer t = new StrataTransformer();
        List<Inbound_Staging__c> r1 = t.transform(Blob.valueOf(csv), ss.Id, false);
        List<Inbound_Staging__c> r2 = t.transform(Blob.valueOf(csv), ss.Id, false);
        System.assertEquals(r1[0].External_Key__c, r2[0].External_Key__c, 'Same GUID must produce same key');
    }
}
