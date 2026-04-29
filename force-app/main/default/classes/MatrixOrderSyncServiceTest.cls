@isTest
private class MatrixOrderSyncServiceTest {

    // ─── Mocks ───────────────────────────────────────────────────────────────

    private class CreateSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setBody('{"matrix_order_id":"MTX-100","status":"created","message":"OK"}');
            return res;
        }
    }

    private class UpdateSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"matrix_order_id":"MTX-100","status":"updated","message":"OK"}');
            return res;
        }
    }

    private class CancelSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"matrix_order_id":"MTX-100","status":"cancelled","message":"OK"}');
            return res;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setBody('{"error":"Service Unavailable"}');
            return res;
        }
    }

    // ─── Test data setup ─────────────────────────────────────────────────────

    private static Advertising_Opportunity__c makeOpportunity(String matrixOrderId) {
        Account acct = new Account(Name = 'Test Advertiser', Matrix_Account_ID__c = 'ACC-TEST');
        insert acct;

        Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
            Name = 'Test Campaign Q1',
            Account__c = acct.Id,
            Status__c = 'Active',
            Total_Budget__c = 75000,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addDays(90),
            Matrix_Order_ID__c = matrixOrderId
        );
        insert opp;
        return opp;
    }

    // ─── Tests ───────────────────────────────────────────────────────────────

    @isTest
    static void testSyncOpportunity_create() {
        Test.setMock(HttpCalloutMock.class, new CreateSuccessMock());
        Advertising_Opportunity__c opp = makeOpportunity(null);

        Test.startTest();
        MatrixOrderSyncService.syncOpportunity(opp.Id, 'CREATE');
        Test.stopTest();

        Advertising_Opportunity__c result = [
            SELECT Matrix_Order_ID__c, Matrix_Sync_Status__c, Matrix_Last_Synced__c
            FROM Advertising_Opportunity__c WHERE Id = :opp.Id
        ];
        System.assertEquals('MTX-100', result.Matrix_Order_ID__c);
        System.assertEquals('Synced', result.Matrix_Sync_Status__c);
        System.assertNotEquals(null, result.Matrix_Last_Synced__c);
    }

    @isTest
    static void testSyncOpportunity_update() {
        Test.setMock(HttpCalloutMock.class, new UpdateSuccessMock());
        Advertising_Opportunity__c opp = makeOpportunity('MTX-100');

        Test.startTest();
        MatrixOrderSyncService.syncOpportunity(opp.Id, 'UPDATE');
        Test.stopTest();

        Advertising_Opportunity__c result = [
            SELECT Matrix_Sync_Status__c FROM Advertising_Opportunity__c WHERE Id = :opp.Id
        ];
        System.assertEquals('Synced', result.Matrix_Sync_Status__c);
    }

    @isTest
    static void testSyncOpportunity_cancel_withMatrixId() {
        Test.setMock(HttpCalloutMock.class, new CancelSuccessMock());
        Advertising_Opportunity__c opp = makeOpportunity('MTX-100');

        Test.startTest();
        MatrixOrderSyncService.syncOpportunity(opp.Id, 'CANCEL');
        Test.stopTest();

        Advertising_Opportunity__c result = [
            SELECT Matrix_Sync_Status__c FROM Advertising_Opportunity__c WHERE Id = :opp.Id
        ];
        System.assertEquals('Synced', result.Matrix_Sync_Status__c);
    }

    @isTest
    static void testSyncOpportunity_cancel_withoutMatrixId_skips() {
        // No HTTP mock needed — the method should return early without making a callout
        Advertising_Opportunity__c opp = makeOpportunity(null);

        Test.startTest();
        MatrixOrderSyncService.syncOpportunity(opp.Id, 'CANCEL');
        Test.stopTest();

        // Status should be unchanged (still null / Not Synced)
        Advertising_Opportunity__c result = [
            SELECT Matrix_Sync_Status__c FROM Advertising_Opportunity__c WHERE Id = :opp.Id
        ];
        System.assertNotEquals('Synced', result.Matrix_Sync_Status__c);
    }

    @isTest
    static void testSyncOpportunity_apiFailure_setsFailedStatus() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        Advertising_Opportunity__c opp = makeOpportunity(null);

        Test.startTest();
        MatrixOrderSyncService.syncOpportunity(opp.Id, 'CREATE');
        Test.stopTest();

        Advertising_Opportunity__c result = [
            SELECT Matrix_Sync_Status__c, Matrix_Sync_Error__c
            FROM Advertising_Opportunity__c WHERE Id = :opp.Id
        ];
        System.assertEquals('Failed', result.Matrix_Sync_Status__c);
        System.assert(String.isNotBlank(result.Matrix_Sync_Error__c));
    }
}
