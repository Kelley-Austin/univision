@isTest
private class MatrixInventorySyncQueueableTest {

    // ─── Mocks ───────────────────────────────────────────────────────────────

    private class InventoryMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"records":['
                + '{"vehicle_external_id":"VEH-001","available_units":42,"last_updated":"2024-06-01T08:00:00Z"},'
                + '{"vehicle_external_id":"VEH-999","available_units":10,"last_updated":"2024-06-01T08:00:00Z"}'
                + ']}'
            );
            return res;
        }
    }

    private class EmptyInventoryMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"records":[]}');
            return res;
        }
    }

    private class ApiErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Server Error"}');
            return res;
        }
    }

    private class StaleInventoryMock implements HttpCalloutMock {
        // Returns data with an older timestamp than what the vehicle already has
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"records":[{"vehicle_external_id":"VEH-001","available_units":5,"last_updated":"2020-01-01T00:00:00Z"}]}'
            );
            return res;
        }
    }

    // ─── Test data ───────────────────────────────────────────────────────────

    private static Vehicle__c makeVehicle(String externalId, Datetime lastUpdated) {
        Vehicle__c v = new Vehicle__c(
            Vehicle_Code__c = externalId,
            External_ID__c = externalId,
            Status__c = 'Active',
            Vehicle_Type__c = 'Network Package',
            Matrix_Avail_Units__c = 100,
            Matrix_Avail_Last_Updated__c = lastUpdated
        );
        insert v;
        return v;
    }

    // ─── Tests ───────────────────────────────────────────────────────────────

    @isTest
    static void testExecute_updatesMatchingVehicle() {
        makeVehicle('VEH-001', null);
        Test.setMock(HttpCalloutMock.class, new InventoryMock());

        Test.startTest();
        System.enqueueJob(new MatrixInventorySyncQueueable(Datetime.now().addHours(-1)));
        Test.stopTest();

        Vehicle__c result = [
            SELECT Matrix_Avail_Units__c, Matrix_Avail_Last_Updated__c
            FROM Vehicle__c WHERE External_ID__c = 'VEH-001'
        ];
        System.assertEquals(42, result.Matrix_Avail_Units__c);
        System.assertNotEquals(null, result.Matrix_Avail_Last_Updated__c);
    }

    @isTest
    static void testExecute_unknownVehicleSkipped() {
        // VEH-999 exists in the mock response but not in Salesforce — should not throw
        Test.setMock(HttpCalloutMock.class, new InventoryMock());

        Test.startTest();
        // Should complete without error even though VEH-999 doesn't exist in SF
        System.enqueueJob(new MatrixInventorySyncQueueable(Datetime.now().addHours(-1)));
        Test.stopTest();
        // If we get here without an exception, the test passes
        System.assert(true);
    }

    @isTest
    static void testExecute_emptyResponse_noUpdates() {
        Vehicle__c v = makeVehicle('VEH-001', null);
        Test.setMock(HttpCalloutMock.class, new EmptyInventoryMock());

        Test.startTest();
        System.enqueueJob(new MatrixInventorySyncQueueable(Datetime.now().addHours(-1)));
        Test.stopTest();

        Vehicle__c result = [SELECT Matrix_Avail_Units__c FROM Vehicle__c WHERE Id = :v.Id];
        System.assertEquals(100, result.Matrix_Avail_Units__c); // unchanged
    }

    @isTest
    static void testExecute_apiError_doesNotThrow() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());

        Test.startTest();
        System.enqueueJob(new MatrixInventorySyncQueueable(Datetime.now().addHours(-1)));
        Test.stopTest();
        // Completes without propagating an exception
        System.assert(true);
    }

    @isTest
    static void testExecute_staleData_doesNotOverwrite() {
        // Vehicle already has a 2024-06-01 timestamp; mock returns 2020 data — should skip
        Datetime recentTs = Datetime.newInstanceGmt(2024, 6, 1, 9, 0, 0);
        Vehicle__c v = makeVehicle('VEH-001', recentTs);
        Test.setMock(HttpCalloutMock.class, new StaleInventoryMock());

        Test.startTest();
        System.enqueueJob(new MatrixInventorySyncQueueable(Datetime.now().addHours(-1)));
        Test.stopTest();

        Vehicle__c result = [SELECT Matrix_Avail_Units__c FROM Vehicle__c WHERE Id = :v.Id];
        System.assertEquals(100, result.Matrix_Avail_Units__c); // not overwritten by stale 5
    }
}
