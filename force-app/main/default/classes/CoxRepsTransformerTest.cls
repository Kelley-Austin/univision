@IsTest
private class CoxRepsTransformerTest {

    @TestSetup
    static void setup() {
        TransformerTestHelper.makeSource('COXREPS', 'CoxRepsTransformer', 'UTF-8');
    }

    private static Source_System__c getSource() {
        return [SELECT Id FROM Source_System__c WHERE Source_Code__c = 'COXREPS' LIMIT 1];
    }

    @IsTest
    static void happyPath_normalizesEmailAeCode() {
        Source_System__c ss = getSource();
        Blob b = Blob.valueOf(TransformerTestHelper.coxRepsCsvHappyPath());
        Test.startTest();
        CoxRepsTransformer t = new CoxRepsTransformer();
        List<Inbound_Staging__c> rows = t.transform(b, ss.Id, false);
        Test.stopTest();
        System.assertEquals(2, rows.size());
        System.assertEquals('Pending', rows[0].Status__c);
        System.assertEquals('john.doe', rows[0].AE_Code__c, 'Email prefix should be extracted');
        System.assertEquals('jane.smith', rows[1].AE_Code__c, 'Email prefix should be extracted');
    }

    @IsTest
    static void aeCodeWithoutAtSign_isPreservedAsIs() {
        CoxRepsTransformer t = new CoxRepsTransformer();
        System.assertEquals('PLAINCOD', t.normalizeAeEmail('PLAINCOD'), 'No @ sign — return as-is');
    }

    @IsTest
    static void blankAeEmail_isPreserved() {
        CoxRepsTransformer t = new CoxRepsTransformer();
        System.assertEquals('', t.normalizeAeEmail(''));
    }

    @IsTest
    static void emptyFile_returnsEmpty() {
        Source_System__c ss = getSource();
        CoxRepsTransformer t = new CoxRepsTransformer();
        Test.startTest();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(''), ss.Id, false);
        Test.stopTest();
        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void malformedRow_isExcluded() {
        Source_System__c ss = getSource();
        String csv = 'advertiser,agency,market_station,revenue_type,net_revenue,ae_email,period\n'
                   + 'JustOneColumn\n';
        Test.startTest();
        CoxRepsTransformer t = new CoxRepsTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals('MALFORMED_ROW', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void blankAdvertiser_isExcluded() {
        Source_System__c ss = getSource();
        String csv = 'advertiser,agency,market_station,revenue_type,net_revenue,ae_email,period\n'
                   + ',MediaCom,KTVW,Local,1000,ae@coxreps.com,2026-03\n';
        Test.startTest();
        CoxRepsTransformer t = new CoxRepsTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals('BLANK_ADVERTISER', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void idempotency_sameRowSameKey() {
        Source_System__c ss = getSource();
        String csv = TransformerTestHelper.coxRepsCsvHappyPath();
        CoxRepsTransformer t = new CoxRepsTransformer();
        List<Inbound_Staging__c> r1 = t.transform(Blob.valueOf(csv), ss.Id, false);
        List<Inbound_Staging__c> r2 = t.transform(Blob.valueOf(csv), ss.Id, false);
        System.assertEquals(r1[0].External_Key__c, r2[0].External_Key__c);
    }
}
