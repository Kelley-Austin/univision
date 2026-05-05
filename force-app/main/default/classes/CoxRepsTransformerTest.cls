@IsTest
private class CoxRepsTransformerTest {

    private static final String HAPPY_PATH_CSV =
        'Advertiser_Name,Agency_Name,AE_Email,Month,Year,Net_Amount,Revenue_Type,Outlet_Code\n' +
        'Home Depot,Initiative,sarah.johnson@coxreps.com,2,2025,45000,Linear TV,WLTV\n' +
        'Target,Havas,mike.chen@coxreps.com,2,2025,22000,Radio,WNFT\n';

    private static final String EMPTY_CSV =
        'Advertiser_Name,Agency_Name,AE_Email,Month,Year,Net_Amount,Revenue_Type,Outlet_Code\n';

    private static final String MALFORMED_CSV =
        'Advertiser_Name,Agency_Name\n' +
        'OnlyTwoCols\n';

    private static Id makeSourceSystem() {
        Source_System__c ss = new Source_System__c(Name = 'CoxReps', Code__c = 'COXREPS', Is_Active__c = true);
        insert ss;
        Load_Batch__c lb = new Load_Batch__c(Source_System__c = ss.Id, Status__c = 'Processing');
        insert lb;
        return lb.Id;
    }

    @IsTest
    static void happyPath_aeEmailStoredAsRawSalespersonCode() {
        Id lbId = makeSourceSystem();
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new CoxRepsTransformer().transform(HAPPY_PATH_CSV, lbId, ssId, 'COXREPS');
        Test.stopTest();

        System.assertEquals(2, rows.size());
        System.assertEquals('sarah.johnson@coxreps.com', rows[0].Raw_Salesperson_Code__c);
        System.assertEquals('mike.chen@coxreps.com', rows[1].Raw_Salesperson_Code__c);
        System.assertEquals('Pending', rows[0].Status__c);
    }

    @IsTest
    static void emptyCsv_zeroResults() {
        Id lbId = makeSourceSystem();
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new CoxRepsTransformer().transform(EMPTY_CSV, lbId, ssId, 'COXREPS');
        Test.stopTest();

        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void malformedCsv_errorRow() {
        Id lbId = makeSourceSystem();
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new CoxRepsTransformer().transform(MALFORMED_CSV, lbId, ssId, 'COXREPS');
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals('Error', rows[0].Status__c);
        System.assertEquals('MALFORMED_ROW', rows[0].Excluding_Rule__c);
    }
}
