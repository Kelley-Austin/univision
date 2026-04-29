@isTest
private class CounterpointIngestionServiceTest {

    @isTest
    static void invocable_calendarFile_createsMatchedRecord() {
        Channel__c ch = new Channel__c(
            Name            = 'KTVU',
            Channel_Code__c = 'KTVU',
            Channel_Type__c = 'TV',
            Status__c       = 'Active'
        );
        insert ch;

        Vehicle__c v = new Vehicle__c(
            Name            = 'GN',
            Vehicle_Code__c = 'GN',
            Status__c       = 'Active'
        );
        insert v;

        Account adv = new Account(Name = 'Test Corp');
        insert adv;

        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'LA,TV Spot,KTVU,Test Corp,GN,03/10/2025,5000.00,4250.00,SVC-001\n';

        ContentVersion cv = new ContentVersion();
        cv.Title          = 'svc_calendar.csv';
        cv.PathOnClient   = 'svc_calendar.csv';
        cv.VersionData    = Blob.valueOf(csv);
        cv.IsMajorVersion = true;
        insert cv;

        CounterpointIngestionService.IngestRequest req = new CounterpointIngestionService.IngestRequest();
        req.contentVersionId = cv.Id;

        Test.startTest();
        CounterpointIngestionService.ingestCounterpointFile(
            new List<CounterpointIngestionService.IngestRequest>{ req }
        );
        Test.stopTest();

        List<Actuals_Record__c> recs = [
            SELECT Date_Type__c, Calendar_Date__c, Status__c, Gross_Revenue__c
            FROM   Actuals_Record__c
        ];
        System.assertEquals(1,                             recs.size());
        System.assertEquals('Calendar',                    recs[0].Date_Type__c);
        System.assertEquals(Date.newInstance(2025, 3, 10), recs[0].Calendar_Date__c);
        System.assertEquals('Matched',                     recs[0].Status__c);
        System.assertEquals(5000.00,                       recs[0].Gross_Revenue__c);
    }

    @isTest
    static void invocable_broadcastFile_createsRecord() {
        Channel__c ch = new Channel__c(
            Name            = 'WUNI',
            Channel_Code__c = 'WUNI',
            Channel_Type__c = 'TV',
            Status__c       = 'Active'
        );
        insert ch;

        Vehicle__c v = new Vehicle__c(
            Name            = 'PN',
            Vehicle_Code__c = 'PN',
            Status__c       = 'Active'
        );
        insert v;

        Account adv = new Account(Name = 'Broadcast Advertiser');
        insert adv;

        String csv =
            'Market,Subcategory,Station,Advertiser,Vehicle,Broadcast_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'NYC,TV Spot,WUNI,Broadcast Advertiser,PN,01/20/2025,3000.00,2550.00,SVC-BRD-001\n';

        ContentVersion cv = new ContentVersion();
        cv.Title          = 'svc_broadcast.csv';
        cv.PathOnClient   = 'svc_broadcast.csv';
        cv.VersionData    = Blob.valueOf(csv);
        cv.IsMajorVersion = true;
        insert cv;

        CounterpointIngestionService.IngestRequest req = new CounterpointIngestionService.IngestRequest();
        req.contentVersionId = cv.Id;

        Test.startTest();
        CounterpointIngestionService.ingestCounterpointFile(
            new List<CounterpointIngestionService.IngestRequest>{ req }
        );
        Test.stopTest();

        Actuals_Record__c rec = [SELECT Date_Type__c, Broadcast_Date__c, Status__c FROM Actuals_Record__c LIMIT 1];
        System.assertEquals('Broadcast',                   rec.Date_Type__c);
        System.assertEquals(Date.newInstance(2025, 1, 20), rec.Broadcast_Date__c);
        System.assertEquals('Matched',                     rec.Status__c);
    }

    @isTest
    static void invocable_multipleRequests_eachStartsBatch() {
        String csv1 =
            'Market,Subcategory,Station,Advertiser,Vehicle,Calendar_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Miami,TV Spot,NONE,NONE,NONE,01/01/2025,100.00,85.00,MULTI-001\n';
        String csv2 =
            'Market,Subcategory,Station,Advertiser,Vehicle,Broadcast_Date,Gross_Revenue,Net_Revenue,Order_ID\n' +
            'Houston,TV Spot,NONE,NONE,NONE,01/06/2025,200.00,170.00,MULTI-002\n';

        ContentVersion cv1 = makeFile('multi1.csv', csv1);
        ContentVersion cv2 = makeFile('multi2.csv', csv2);

        CounterpointIngestionService.IngestRequest r1 = new CounterpointIngestionService.IngestRequest();
        r1.contentVersionId = cv1.Id;
        CounterpointIngestionService.IngestRequest r2 = new CounterpointIngestionService.IngestRequest();
        r2.contentVersionId = cv2.Id;

        Test.startTest();
        CounterpointIngestionService.ingestCounterpointFile(
            new List<CounterpointIngestionService.IngestRequest>{ r1, r2 }
        );
        Test.stopTest();

        // Both batches ran — 2 records created (both unmatched since station/vehicle/advertiser don't exist)
        System.assertEquals(2, [SELECT COUNT() FROM Actuals_Record__c]);
    }

    private static ContentVersion makeFile(String fileName, String content) {
        ContentVersion cv = new ContentVersion();
        cv.Title          = fileName;
        cv.PathOnClient   = fileName;
        cv.VersionData    = Blob.valueOf(content);
        cv.IsMajorVersion = true;
        insert cv;
        return cv;
    }
}
