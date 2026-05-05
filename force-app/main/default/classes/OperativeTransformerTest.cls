@IsTest
private class OperativeTransformerTest {

    private static final String HAPPY_PATH_CSV =
        'Advertiser_Name,Agency_Name,Rep_Code,Cal_Month,Cal_Year,Cal_Net,Broadcast_Month,Broadcast_Year,Broadcast_Net,Revenue_Type,Outlet_Code\n' +
        'Verizon,GroupM,TORRES_R,1,2025,100000,1,2025,95000,Linear TV,KMEX\n';

    private static final String EMPTY_CSV =
        'Advertiser_Name,Agency_Name,Rep_Code,Cal_Month,Cal_Year,Cal_Net,Broadcast_Month,Broadcast_Year,Broadcast_Net,Revenue_Type,Outlet_Code\n';

    private static final String MALFORMED_CSV =
        'Advertiser_Name,Agency_Name\n' +
        'OnlyTwo\n';

    private static Id makeSourceSystem() {
        Source_System__c ss = new Source_System__c(Name = 'Operative', Code__c = 'OPERATIVE', Source_Code__c = 'OPERATIVE', Transformer_Class__c = 'OperativeTransformer', Is_Active__c = true);
        insert ss;
        Load_Batch__c lb = new Load_Batch__c(Source_System__c = ss.Id, Status__c = 'Processing');
        insert lb;
        return lb.Id;
    }

    @IsTest
    static void happyPath_oneInputRow_twoOutputRows() {
        Id lbId = makeSourceSystem();
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new OperativeTransformer().transform(HAPPY_PATH_CSV, lbId, ssId, 'OPERATIVE');
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'One input row produces Calendar + Broadcast rows');
        System.assertEquals('Calendar', rows[0].Calendar_Type__c);
        System.assertEquals('Broadcast', rows[1].Calendar_Type__c);
        System.assertEquals(100000, rows[0].Revenue_Amount__c);
        System.assertEquals(95000, rows[1].Revenue_Amount__c);
        System.assertEquals(1, rows[0].Period_Month__c);
        System.assertEquals(2025, rows[0].Period_Year__c);
        System.assertEquals(1, rows[1].Period_Month__c);
        System.assertEquals(2025, rows[1].Period_Year__c);
        System.assertEquals('Linear TV', rows[0].Revenue_Type__c);
        System.assertEquals('Linear TV', rows[1].Revenue_Type__c);
    }

    @IsTest
    static void emptyCsv_zeroResults() {
        Id lbId = makeSourceSystem();
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new OperativeTransformer().transform(EMPTY_CSV, lbId, ssId, 'OPERATIVE');
        Test.stopTest();

        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void malformedCsv_errorRow() {
        Id lbId = makeSourceSystem();
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new OperativeTransformer().transform(MALFORMED_CSV, lbId, ssId, 'OPERATIVE');
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals('Error', rows[0].Status__c);
        System.assertEquals('MALFORMED_ROW', rows[0].Excluding_Rule__c);
    }
}
