@IsTest
private class MatrixInventorySyncQueueableTest {

    private class SyncMock implements HttpCalloutMock {
        private final String body;
        SyncMock(String body) { this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(body);
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    @TestSetup
    static void setup() {
        insert new List<Vehicle__c>{
            new Vehicle__c(Name = 'Univision Network'),
            new Vehicle__c(Name = 'UniMás'),
            new Vehicle__c(Name = 'Galavision')
        };
    }

    @IsTest
    static void execute_scheduledSync_updatesMatchingVehicles() {
        String body = '{"inventory":['
            + '{"adSpaceId":"AS-001","vehicleName":"Univision Network","status":"active"},'
            + '{"adSpaceId":"AS-002","vehicleName":"UniMás","status":"active"}'
            + ']}';
        Test.setMock(HttpCalloutMock.class, new SyncMock(body));

        Test.startTest();
        System.enqueueJob(new MatrixInventorySyncQueueable(false));
        Test.stopTest();

        Map<String, Vehicle__c> byName = new Map<String, Vehicle__c>();
        for (Vehicle__c v : [SELECT Name, Media_Cloud_Ad_Space_ID__c, Matrix_Sync_Status__c FROM Vehicle__c]) {
            byName.put(v.Name, v);
        }

        System.assertEquals('AS-001', byName.get('Univision Network').Media_Cloud_Ad_Space_ID__c);
        System.assertEquals('Synced', byName.get('Univision Network').Matrix_Sync_Status__c);
        System.assertEquals('AS-002', byName.get('UniMás').Media_Cloud_Ad_Space_ID__c);
        System.assertEquals(null, byName.get('Galavision').Media_Cloud_Ad_Space_ID__c, 'Unmatched vehicle should remain null');

        List<Matrix_Sync_Log__c> logs = [SELECT Status__c, Records_Processed__c, Sync_Type__c FROM Matrix_Sync_Log__c];
        System.assertEquals(1, logs.size(), 'One log record should be written');
        System.assertEquals('Success', logs[0].Status__c);
        System.assertEquals(2, Integer.valueOf(logs[0].Records_Processed__c));
        System.assertEquals('Scheduled', logs[0].Sync_Type__c);
    }

    @IsTest
    static void execute_manualSync_logTypeIsManual() {
        String body = '{"inventory":[{"adSpaceId":"AS-001","vehicleName":"Univision Network","status":"active"}]}';
        Test.setMock(HttpCalloutMock.class, new SyncMock(body));

        Test.startTest();
        System.enqueueJob(new MatrixInventorySyncQueueable(true));
        Test.stopTest();

        List<Matrix_Sync_Log__c> logs = [SELECT Sync_Type__c FROM Matrix_Sync_Log__c];
        System.assertEquals('Manual', logs[0].Sync_Type__c);
    }

    @IsTest
    static void execute_emptyApiResponse_logsSuccessWithZeroRecords() {
        Test.setMock(HttpCalloutMock.class, new SyncMock('{"inventory":[]}'));

        Test.startTest();
        System.enqueueJob(new MatrixInventorySyncQueueable(false));
        Test.stopTest();

        List<Matrix_Sync_Log__c> logs = [SELECT Status__c, Records_Processed__c, Error_Detail__c FROM Matrix_Sync_Log__c];
        System.assertEquals(1, logs.size());
        System.assertEquals('Success', logs[0].Status__c);
        System.assertEquals(0, Integer.valueOf(logs[0].Records_Processed__c));
        System.assert(logs[0].Error_Detail__c.contains('0 active inventory'), 'Error detail should explain empty response');
    }

    @IsTest
    static void execute_apiError_logsErrorStatus() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        System.enqueueJob(new MatrixInventorySyncQueueable(false));
        Test.stopTest();

        List<Matrix_Sync_Log__c> logs = [SELECT Status__c, Error_Detail__c FROM Matrix_Sync_Log__c];
        System.assertEquals(1, logs.size());
        System.assertEquals('Error', logs[0].Status__c);
        System.assert(String.isNotBlank(logs[0].Error_Detail__c), 'Error detail should be populated');
    }

    @IsTest
    static void execute_caseInsensitiveNameMatch() {
        String body = '{"inventory":[{"adSpaceId":"AS-001","vehicleName":"UNIVISION NETWORK","status":"active"}]}';
        Test.setMock(HttpCalloutMock.class, new SyncMock(body));

        Test.startTest();
        System.enqueueJob(new MatrixInventorySyncQueueable(false));
        Test.stopTest();

        Vehicle__c v = [SELECT Media_Cloud_Ad_Space_ID__c FROM Vehicle__c WHERE Name = 'Univision Network' LIMIT 1];
        System.assertEquals('AS-001', v.Media_Cloud_Ad_Space_ID__c, 'Name match should be case-insensitive');
    }

    @IsTest
    static void execute_noChangeWhenIdAlreadyMatches() {
        Vehicle__c v = [SELECT Id FROM Vehicle__c WHERE Name = 'Univision Network' LIMIT 1];
        v.Media_Cloud_Ad_Space_ID__c = 'AS-001';
        update v;

        String body = '{"inventory":[{"adSpaceId":"AS-001","vehicleName":"Univision Network","status":"active"}]}';
        Test.setMock(HttpCalloutMock.class, new SyncMock(body));

        Test.startTest();
        System.enqueueJob(new MatrixInventorySyncQueueable(false));
        Test.stopTest();

        List<Matrix_Sync_Log__c> logs = [SELECT Records_Processed__c FROM Matrix_Sync_Log__c];
        System.assertEquals(0, Integer.valueOf(logs[0].Records_Processed__c), 'No DML should occur when ID is unchanged');
    }
}
