@IsTest
private class OperativeTransformerTest {

    @TestSetup
    static void setup() {
        TransformerTestHelper.makeSource('OPERATIVE', 'OperativeTransformer', 'UTF-8');
    }

    private static Source_System__c getSource() {
        return [SELECT Id FROM Source_System__c WHERE Source_Code__c = 'OPERATIVE' LIMIT 1];
    }

    @IsTest
    static void happyPath_producesCalendarAndBroadcastRows() {
        Source_System__c ss = getSource();
        Blob b = Blob.valueOf(TransformerTestHelper.operativeCsvHappyPath());
        Test.startTest();
        OperativeTransformer t = new OperativeTransformer();
        List<Inbound_Staging__c> rows = t.transform(b, ss.Id, false);
        Test.stopTest();
        // Row 1: periods differ → 2 rows. Row 2: same period → 1 row (no duplicate)
        System.assertEquals(3, rows.size(), 'Row1→2 rows; Row2→1 row (same period)');
        // Check row 1 calendar
        System.assertEquals('Digital - Calendar', rows[0].Revenue_Type__c);
        System.assertEquals('2026-03', rows[0].Broadcast_Period__c);
        // Check row 1 broadcast
        System.assertEquals('Digital - Broadcast', rows[1].Revenue_Type__c);
        System.assertEquals('2026-04', rows[1].Broadcast_Period__c);
        // Row 2 — only calendar (same period)
        System.assertEquals('TV - Calendar', rows[2].Revenue_Type__c);
        System.assertEquals('2026-03', rows[2].Broadcast_Period__c);
    }

    @IsTest
    static void emptyFile_returnsEmpty() {
        Source_System__c ss = getSource();
        Test.startTest();
        OperativeTransformer t = new OperativeTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(''), ss.Id, false);
        Test.stopTest();
        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void malformedRow_isExcluded() {
        Source_System__c ss = getSource();
        String csv = 'advertiser_name,agency_name,station,product_type,gross_revenue,sales_rep_id,calendar_month,broadcast_month\n'
                   + 'OnlyOne\n';
        Test.startTest();
        OperativeTransformer t = new OperativeTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals('MALFORMED_ROW', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void blankAdvertiser_isExcluded() {
        Source_System__c ss = getSource();
        String csv = 'advertiser_name,agency_name,station,product_type,gross_revenue,sales_rep_id,calendar_month,broadcast_month\n'
                   + ',Agency,KTVW,TV,1000,R1,2026-03,2026-03\n';
        Test.startTest();
        OperativeTransformer t = new OperativeTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        Test.stopTest();
        System.assertEquals('BLANK_ADVERTISER', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void idempotency_calAndBcastHaveDifferentKeys() {
        Source_System__c ss = getSource();
        String csv = 'advertiser_name,agency_name,station,product_type,gross_revenue,sales_rep_id,calendar_month,broadcast_month\n'
                   + 'Acme Corp,Agency,KTVW,TV,5000,R1,2026-03,2026-04\n';
        OperativeTransformer t = new OperativeTransformer();
        List<Inbound_Staging__c> rows = t.transform(Blob.valueOf(csv), ss.Id, false);
        System.assertEquals(2, rows.size());
        System.assertNotEquals(rows[0].External_Key__c, rows[1].External_Key__c,
            'Calendar and broadcast rows must have different external keys');
        // Re-run: keys must be stable
        List<Inbound_Staging__c> rows2 = t.transform(Blob.valueOf(csv), ss.Id, false);
        System.assertEquals(rows[0].External_Key__c, rows2[0].External_Key__c);
    }
}
