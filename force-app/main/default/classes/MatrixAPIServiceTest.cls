@isTest
private class MatrixAPIServiceTest {

    // ─── Mock implementations ────────────────────────────────────────────────

    private class SuccessCreateMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setBody('{"matrix_order_id":"MTX-001","status":"created","message":"OK"}');
            return res;
        }
    }

    private class SuccessUpdateMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"matrix_order_id":"MTX-001","status":"updated","message":"OK"}');
            return res;
        }
    }

    private class SuccessCancelMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"matrix_order_id":"MTX-001","status":"cancelled","message":"OK"}');
            return res;
        }
    }

    private class InventoryMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"records":[{"vehicle_external_id":"VEH-001","available_units":50,"last_updated":"2024-01-15T10:30:00Z"}]}');
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    private class EmptyInventoryMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"records":null}');
            return res;
        }
    }

    // ─── Tests ───────────────────────────────────────────────────────────────

    @isTest
    static void testCreateOrder_success() {
        Test.setMock(HttpCalloutMock.class, new SuccessCreateMock());

        MatrixAPIService.OrderPayload p = new MatrixAPIService.OrderPayload();
        p.salesforce_id = 'a001000000000001';
        p.matrix_account_id = 'ACC-123';
        p.order_name = 'Test Campaign';
        p.status = 'Active';
        p.total_budget = 50000;

        Test.startTest();
        MatrixAPIService.OrderResponse resp = MatrixAPIService.createOrder(p);
        Test.stopTest();

        System.assertEquals('MTX-001', resp.matrix_order_id);
        System.assertEquals('created', resp.status);
    }

    @isTest
    static void testUpdateOrder_success() {
        Test.setMock(HttpCalloutMock.class, new SuccessUpdateMock());

        MatrixAPIService.OrderPayload p = new MatrixAPIService.OrderPayload();
        p.salesforce_id = 'a001000000000001';
        p.order_name = 'Updated Campaign';

        Test.startTest();
        MatrixAPIService.OrderResponse resp = MatrixAPIService.updateOrder('MTX-001', p);
        Test.stopTest();

        System.assertEquals('MTX-001', resp.matrix_order_id);
        System.assertEquals('updated', resp.status);
    }

    @isTest
    static void testCancelOrder_success() {
        Test.setMock(HttpCalloutMock.class, new SuccessCancelMock());

        Test.startTest();
        MatrixAPIService.OrderResponse resp = MatrixAPIService.cancelOrder('MTX-001');
        Test.stopTest();

        System.assertEquals('cancelled', resp.status);
    }

    @isTest
    static void testGetInventoryChanges_success() {
        Test.setMock(HttpCalloutMock.class, new InventoryMock());

        Test.startTest();
        List<MatrixAPIService.InventoryRecord> records =
            MatrixAPIService.getInventoryChanges(Datetime.now().addHours(-1));
        Test.stopTest();

        System.assertEquals(1, records.size());
        System.assertEquals('VEH-001', records[0].vehicle_external_id);
        System.assertEquals(50, records[0].available_units);
    }

    @isTest
    static void testGetInventoryChanges_emptyResponse() {
        Test.setMock(HttpCalloutMock.class, new EmptyInventoryMock());

        Test.startTest();
        List<MatrixAPIService.InventoryRecord> records =
            MatrixAPIService.getInventoryChanges(Datetime.now().addHours(-1));
        Test.stopTest();

        System.assertEquals(0, records.size());
    }

    @isTest
    static void testApiError_throwsMatrixException() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        MatrixAPIService.OrderPayload p = new MatrixAPIService.OrderPayload();
        p.order_name = 'Fail Campaign';

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            MatrixAPIService.createOrder(p);
        } catch (MatrixAPIService.MatrixException ex) {
            exceptionThrown = true;
            System.assert(ex.getMessage().contains('500'));
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected MatrixException for 500 response');
    }

    @isTest
    static void testInventoryFetchError_throwsMatrixException() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            MatrixAPIService.getInventoryChanges(Datetime.now());
        } catch (MatrixAPIService.MatrixException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected MatrixException for inventory 500');
    }
}
