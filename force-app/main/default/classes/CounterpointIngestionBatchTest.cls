@isTest
private class CounterpointIngestionBatchTest {

    // ─── Shared test data ─────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Channel__c ch = new Channel__c(
            Name           = 'WFUU',
            Channel_Code__c = 'WFUU',
            Channel_Type__c = 'TV',
            Status__c      = 'Active'
        );
        insert ch;

        Vehicle__c v = new Vehicle__c(
            Name           = 'BMF',
            Vehicle_Code__c = 'BMF',
            Status__c      = 'Active'
        );
        insert v;

        Account adv = new Account(Name = 'Acme Corp');
        insert adv;
    }

    // ─── Calendar-date variant ────────────────────────────────────────────────

    @isTest
    static void calendarVariant_createsRecordsWithCorrectDateType() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Miami,TV Spot,WFUU,Acme Corp,BMF,01/15/2025,1000.00,850.00,CAL-001\n' +
            'Miami,TV Spot,WFUU,Acme Corp,BMF,01/22/2025,2000.00,1700.00,CAL-002\n';

        ContentVersion cv = makeFile('calendar_test.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        List<Actuals_Record__c> recs = [
            SELECT Date_Type__c, Calendar_Date__c, Broadcast_Date__c, Status__c,
                   Gross_Revenue__c, Net_Revenue__c, Agency_Commission__c
            FROM   Actuals_Record__c
            ORDER BY Counterpoint_Order_ID__c
        ];
        System.assertEquals(2, recs.size(), 'Should create 2 records');
        System.assertEquals('Calendar',                   recs[0].Date_Type__c);
        System.assertEquals(Date.newInstance(2025, 1, 15), recs[0].Calendar_Date__c);
        System.assertEquals(null,                          recs[0].Broadcast_Date__c);
        System.assertEquals('Matched',                    recs[0].Status__c);
        System.assertEquals(1000.00,                      recs[0].Gross_Revenue__c);
        System.assertEquals(850.00,                       recs[0].Net_Revenue__c);
        System.assertEquals(150.00,                       recs[0].Agency_Commission__c);
    }

    @isTest
    static void calendarVariant_airDateColumnAlias() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Air_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Houston,Radio Spot,WFUU,Acme Corp,BMF,03/05/2025,500.00,425.00,AIR-001\n';

        ContentVersion cv = makeFile('air_date_test.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        Actuals_Record__c rec = [SELECT Date_Type__c, Calendar_Date__c FROM Actuals_Record__c LIMIT 1];
        System.assertEquals('Calendar', rec.Date_Type__c);
        System.assertEquals(Date.newInstance(2025, 3, 5), rec.Calendar_Date__c);
    }

    // ─── Broadcast-date variant ───────────────────────────────────────────────

    @isTest
    static void broadcastVariant_createsRecordsWithCorrectDateType() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Broadcast_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Miami,TV Spot,WFUU,Acme Corp,BMF,01/20/2025,1500.00,1275.00,BRD-001\n';

        ContentVersion cv = makeFile('broadcast_test.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        Actuals_Record__c rec = [
            SELECT Date_Type__c, Broadcast_Date__c, Calendar_Date__c, Status__c
            FROM   Actuals_Record__c
            LIMIT  1
        ];
        System.assertEquals('Broadcast',                   rec.Date_Type__c);
        System.assertEquals(Date.newInstance(2025, 1, 20), rec.Broadcast_Date__c);
        System.assertEquals(null,                          rec.Calendar_Date__c);
        System.assertEquals('Matched',                     rec.Status__c);
    }

    @isTest
    static void broadcastVariant_bcastDateColumnAlias() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Bcast_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'LA,TV Spot,WFUU,Acme Corp,BMF,02/03/2025,800.00,680.00,BCT-001\n';

        ContentVersion cv = makeFile('bcast_date_test.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        Actuals_Record__c rec = [SELECT Date_Type__c FROM Actuals_Record__c LIMIT 1];
        System.assertEquals('Broadcast', rec.Date_Type__c);
    }

    // ─── Lookup matching ──────────────────────────────────────────────────────

    @isTest
    static void unmatchedStation_setsStatusUnmatchedWithNote() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Houston,TV Spot,UNKNOWN,Acme Corp,BMF,02/01/2025,500.00,425.00,UNM-001\n';

        ContentVersion cv = makeFile('unmatched_station.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        Actuals_Record__c rec = [SELECT Status__c, Match_Notes__c, Station__c FROM Actuals_Record__c LIMIT 1];
        System.assertEquals('Unmatched', rec.Status__c);
        System.assertEquals(null,        rec.Station__c);
        System.assert(rec.Match_Notes__c.contains('Station not found: UNKNOWN'));
    }

    @isTest
    static void unmatchedVehicle_setsStatusUnmatchedWithNote() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Miami,TV Spot,WFUU,Acme Corp,UNKNOWN_VEH,02/10/2025,600.00,510.00,UNM-002\n';

        ContentVersion cv = makeFile('unmatched_vehicle.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        Actuals_Record__c rec = [SELECT Status__c, Match_Notes__c FROM Actuals_Record__c LIMIT 1];
        System.assertEquals('Unmatched', rec.Status__c);
        System.assert(rec.Match_Notes__c.contains('Vehicle not found: UNKNOWN_VEH'));
    }

    @isTest
    static void unmatchedAdvertiser_setsStatusUnmatchedWithNote() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Miami,TV Spot,WFUU,No Such Advertiser,BMF,02/15/2025,700.00,595.00,UNM-003\n';

        ContentVersion cv = makeFile('unmatched_advertiser.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        Actuals_Record__c rec = [SELECT Status__c, Match_Notes__c, Advertiser__c FROM Actuals_Record__c LIMIT 1];
        System.assertEquals('Unmatched', rec.Status__c);
        System.assertEquals(null,        rec.Advertiser__c);
        System.assert(rec.Match_Notes__c.contains('Advertiser not found'));
    }

    // ─── Quoted CSV ───────────────────────────────────────────────────────────

    @isTest
    static void quotedFields_parsedCorrectly() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            '"Miami, FL",TV Spot,WFUU,"Acme, Corp",BMF,01/15/2025,"$1,000.00","850.00",QUO-001\n';

        ContentVersion cv = makeFile('quoted_test.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        Actuals_Record__c rec = [SELECT Market__c, Gross_Revenue__c, Advertiser_Name__c FROM Actuals_Record__c LIMIT 1];
        System.assertEquals('Miami, FL', rec.Market__c);
        System.assertEquals(1000.00,     rec.Gross_Revenue__c);
        System.assertEquals('Acme, Corp', rec.Advertiser_Name__c);
    }

    // ─── Agency commission ────────────────────────────────────────────────────

    @isTest
    static void agencyCommission_explicitColumnUsedWhenPresent() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Agency_Commission,Order_ID\n' +
            'Miami,TV Spot,WFUU,Acme Corp,BMF,01/15/2025,1000.00,850.00,120.00,COM-001\n';

        ContentVersion cv = makeFile('commission_test.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        Actuals_Record__c rec = [SELECT Agency_Commission__c FROM Actuals_Record__c LIMIT 1];
        System.assertEquals(120.00, rec.Agency_Commission__c, 'Should use explicit commission column');
    }

    // ─── Edge cases ───────────────────────────────────────────────────────────

    @isTest
    static void emptyFile_createsNoRecords() {
        ContentVersion cv = makeFile('empty.csv', '');

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Actuals_Record__c]);
    }

    @isTest
    static void headerOnlyFile_createsNoRecords() {
        String csv = 'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n';
        ContentVersion cv = makeFile('header_only.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Actuals_Record__c]);
    }

    @isTest
    static void rowMissingOrderId_skipped() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Miami,TV Spot,WFUU,Acme Corp,BMF,01/15/2025,1000.00,850.00,\n' +
            'Miami,TV Spot,WFUU,Acme Corp,BMF,01/22/2025,2000.00,1700.00,SKIP-002\n';

        ContentVersion cv = makeFile('missing_order_id.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Actuals_Record__c], 'Row without Order_ID should be skipped');
    }

    @isTest
    static void upsert_idempotent_secondRunUpdatesNotDuplicates() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Miami,TV Spot,WFUU,Acme Corp,BMF,01/15/2025,1000.00,850.00,UPS-001\n';
        ContentVersion cv1 = makeFile('upsert1.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv1.Id, cv1.Title), 200);
        Test.stopTest();

        // Second load: same Order_ID, updated revenue
        String csv2 = csv.replace('1000.00', '1100.00');
        ContentVersion cv2 = makeFile('upsert2.csv', csv2);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv2.Id, cv2.Title), 200);
        Test.stopTest();

        List<Actuals_Record__c> recs = [
            SELECT Gross_Revenue__c
            FROM   Actuals_Record__c
            WHERE  Counterpoint_Order_ID__c = 'UPS-001'
        ];
        System.assertEquals(1,       recs.size(),            'Should not create a duplicate');
        System.assertEquals(1100.00, recs[0].Gross_Revenue__c, 'Second run should update revenue');
    }

    @isTest
    static void blankLineBetweenRows_ignored() {
        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Miami,TV Spot,WFUU,Acme Corp,BMF,01/15/2025,1000.00,850.00,BLK-001\n' +
            '\n' +
            'Miami,TV Spot,WFUU,Acme Corp,BMF,01/22/2025,2000.00,1700.00,BLK-002\n';

        ContentVersion cv = makeFile('blank_lines.csv', csv);

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch(cv.Id, cv.Title), 200);
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Actuals_Record__c]);
    }

    // ─── Helper ───────────────────────────────────────────────────────────────

    private static ContentVersion makeFile(String fileName, String content) {
        ContentVersion cv = new ContentVersion();
        cv.Title         = fileName;
        cv.PathOnClient  = fileName;
        cv.VersionData   = Blob.valueOf(content);
        cv.IsMajorVersion = true;
        insert cv;
        return cv;
    }
}
