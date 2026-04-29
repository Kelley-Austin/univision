@IsTest
private class CounterpointTransformerTest {

    private static final String CALENDAR_CSV =
        'Advertiser_Name,Agency_Name,Sales_Rep,Month,Year,Net_Amount,Unit_Code,Outlet_Code,Revenue_Type\n' +
        'Kraft Heinz,Wavemaker,DAVIS_B,3,2025,60000,CP-2025-001,KMEX,Linear TV\n' +
        'General Mills,Hearts & Science,PATEL_N,3,2025,35000,CP-2025-002,KUVN,Linear TV\n';

    private static final String EMPTY_CSV =
        'Advertiser_Name,Agency_Name,Sales_Rep,Month,Year,Net_Amount,Unit_Code,Outlet_Code,Revenue_Type\n';

    private static final String MALFORMED_CSV =
        'Advertiser_Name,Agency_Name\n' +
        'TooShort\n';

    private static Id makeSourceSystem(String code) {
        Source_System__c ss = new Source_System__c(Name = code, Code__c = code, Is_Active__c = true);
        insert ss;
        Load_Batch__c lb = new Load_Batch__c(Source_System__c = ss.Id, Status__c = 'Processing');
        insert lb;
        return lb.Id;
    }

    @IsTest
    static void calendarSourceCode_calendarTypeCalendar_unitCodePopulated() {
        Id lbId = makeSourceSystem('COUNTERPOINT_CALENDAR');
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new CounterpointTransformer().transform(CALENDAR_CSV, lbId, ssId, 'COUNTERPOINT_CALENDAR');
        Test.stopTest();

        System.assertEquals(2, rows.size());
        System.assertEquals('Calendar', rows[0].Calendar_Type__c);
        System.assertEquals('CP-2025-001', rows[0].Unit_Code__c);
        System.assertEquals('Kraft Heinz', rows[0].Raw_Advertiser_Name__c);
        System.assertEquals(3, rows[0].Period_Month__c);
        System.assertEquals(2025, rows[0].Period_Year__c);
    }

    @IsTest
    static void broadcastSourceCode_calendarTypeBroadcast() {
        Id lbId = makeSourceSystem('COUNTERPOINT_BROADCAST');
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new CounterpointTransformer().transform(CALENDAR_CSV, lbId, ssId, 'COUNTERPOINT_BROADCAST');
        Test.stopTest();

        System.assertEquals(2, rows.size());
        System.assertEquals('Broadcast', rows[0].Calendar_Type__c);
    }

    @IsTest
    static void emptyCsv_zeroResults() {
        Id lbId = makeSourceSystem('COUNTERPOINT_CALENDAR');
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new CounterpointTransformer().transform(EMPTY_CSV, lbId, ssId, 'COUNTERPOINT_CALENDAR');
        Test.stopTest();

        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void malformedCsv_errorRow() {
        Id lbId = makeSourceSystem('COUNTERPOINT_CALENDAR');
        Id ssId = [SELECT Source_System__c FROM Load_Batch__c WHERE Id = :lbId].Source_System__c;

        Test.startTest();
        List<Inbound_Staging__c> rows = new CounterpointTransformer().transform(MALFORMED_CSV, lbId, ssId, 'COUNTERPOINT_CALENDAR');
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals('Error', rows[0].Status__c);
        System.assertEquals('MALFORMED_ROW', rows[0].Excluding_Rule__c);
    }
}
