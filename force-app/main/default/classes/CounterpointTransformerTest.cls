@IsTest
private class CounterpointTransformerTest {

    @TestSetup
    static void setup() {
        TransformerTestHelper.makeSource('COUNTERPOINT', 'CounterpointTransformer', 'CP1252');
    }

    private static Source_System__c getSource() {
        return [SELECT Id FROM Source_System__c WHERE Source_Code__c = 'COUNTERPOINT' LIMIT 1];
    }

    @IsTest
    static void happyPath_parsesTwoDataRows() {
        Source_System__c ss = getSource();
        Blob b = Blob.valueOf(TransformerTestHelper.counterpointCsvHappyPath());
        Test.startTest();
        CounterpointTransformer t = new CounterpointTransformer();
        List<Inbound_Staging__c> rows = t.transform(b, ss.Id, false);
        Test.stopTest();
        System.assertEquals(2, rows.size());
        System.assertEquals('Pending', rows[0].Status__c);
        System.assertEquals('Acme Corp', rows[0].Advertiser_Name__c);
        System.assertEquals('JD', rows[0].AE_Code__c);
        System.assertEquals(12500.00, rows[0].Revenue_Amount__c);
    }

    @IsTest
    static void emptyFile_returnsEmpty() {
        Source_System__c ss = getSource();
        Test.startTest();
        CounterpointTransformer t = new CounterpointTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(''), ss.Id, false);
        Test.stopTest();
        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void malformedRow_isExcluded() {
        Source_System__c ss = getSource();
        String csv = 'advertiser,agency,station,type,amount,ae,period\nTooShort\n';
        Test.startTest();
        CounterpointTransformer t = new CounterpointTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals('MALFORMED_ROW', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void blankAdvertiser_isExcluded() {
        Source_System__c ss = getSource();
        String csv = 'advertiser,agency,station,type,amount,ae,period\n,Agency,KTVW,Local,1000,AE,2026-03\n';
        Test.startTest();
        CounterpointTransformer t = new CounterpointTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals('BLANK_ADVERTISER', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void idempotency_sameRowSameKey() {
        Source_System__c ss = getSource();
        String csv = TransformerTestHelper.counterpointCsvHappyPath();
        CounterpointTransformer t = new CounterpointTransformer();
        List<Inbound_Staging__c> r1 = t.transform(Blob.valueOf(csv), ss.Id, false);
        List<Inbound_Staging__c> r2 = t.transform(Blob.valueOf(csv), ss.Id, false);
        System.assertEquals(r1[0].External_Key__c, r2[0].External_Key__c);
    }

    @IsTest
    static void cp1252SpecialChars_doNotThrow() {
        Source_System__c ss = getSource();
        // Em-dash and smart quotes in advertiser name (common in CP1252 files)
        String csv = 'advertiser,agency,station,type,amount,ae,period\n'
                   + 'Café Media,Agency,KTVW,Local,500,AE,2026-03\n';
        Test.startTest();
        CounterpointTransformer t = new CounterpointTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals(1, rows.size());
        System.assertEquals('Pending', rows[0].Status__c);
    }
}
