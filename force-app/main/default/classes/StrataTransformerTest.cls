@IsTest
private class StrataTransformerTest {

    private static final String HAPPY_PATH_CSV =
        'Advertiser_ID,Advertiser_Name,Agency_Name,Salesperson,Month,Year,Net_Amount,Revenue_Type,Outlet_Code\n' +
        '11111111-0000-0000-0000-000000000001,Ford Motor Company,OMD,ROGERS_T,1,2025,75000,Linear TV,KMEX\n' +
        '22222222-0000-0000-0000-000000000002,McDonald\'s,DDB,CHEN_A,1,2025,30000,Linear TV,KUVN\n';

    private static final String NULL_GUID_CSV =
        'Advertiser_ID,Advertiser_Name,Agency_Name,Salesperson,Month,Year,Net_Amount,Revenue_Type,Outlet_Code\n' +
        '00000000-0000-0000-0000-000000000000,Unknown,Unknown,SMITH_J,1,2025,5000,Linear TV,KMEX\n';

    private static final String EMPTY_CSV =
        'Advertiser_ID,Advertiser_Name,Agency_Name,Salesperson,Month,Year,Net_Amount,Revenue_Type,Outlet_Code\n';

    private static final String MALFORMED_CSV =
        'Advertiser_ID,Advertiser_Name\n' +
        'bad_data_row\n';

    private static Id makeSourceSystem() {
        Source_System__c ss = new Source_System__c(Name = 'Strata', Code__c = 'STRATA', Is_Active__c = true);
        insert ss;
        Load_Batch__c lb = new Load_Batch__c(Source_System__c = ss.Id, Status__c = 'Processing');
        insert lb;
        return lb.Id;
    }

    @IsTest
    static void happyPath_twoValidRows_twoPending() {
        Id lbId = makeSourceSystem();
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new StrataTransformer().transform(HAPPY_PATH_CSV, lbId, ssId, 'STRATA');
        Test.stopTest();

        System.assertEquals(2, rows.size());
        System.assertEquals('Pending', rows[0].Status__c);
        System.assertEquals('Pending', rows[1].Status__c);
        System.assertEquals('Ford Motor Company', rows[0].Raw_Advertiser_Name__c);
    }

    @IsTest
    static void nullGuid_statusExcluded_ruleNullGuidAdvertiser() {
        Id lbId = makeSourceSystem();
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new StrataTransformer().transform(NULL_GUID_CSV, lbId, ssId, 'STRATA');
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals('Excluded', rows[0].Status__c);
        System.assertEquals('NULL_GUID_ADVERTISER', rows[0].Excluding_Rule__c);
    }

    @IsTest
    static void emptyCsv_zeroResults() {
        Id lbId = makeSourceSystem();
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new StrataTransformer().transform(EMPTY_CSV, lbId, ssId, 'STRATA');
        Test.stopTest();

        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void malformedCsv_errorRow() {
        Id lbId = makeSourceSystem();
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new StrataTransformer().transform(MALFORMED_CSV, lbId, ssId, 'STRATA');
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals('Error', rows[0].Status__c);
        System.assertEquals('MALFORMED_ROW', rows[0].Excluding_Rule__c);
    }
}
