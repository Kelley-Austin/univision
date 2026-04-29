@IsTest
private class MatrixApiServiceTest {

    private class InventoryMock implements HttpCalloutMock {
        private final Integer code;
        private final String body;
        InventoryMock(Integer code, String body) { this.code = code; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setBody(body);
            return res;
        }
    }

    private static final String GOOD_INVENTORY = '{"inventory":[{"adSpaceId":"AS-001","vehicleName":"Univision Network","status":"active"},{"adSpaceId":"AS-002","vehicleName":"UniMás","status":"active"}]}';
    private static final String GOOD_PLAN = '{"mediaPlanId":"MP-99"}';

    @IsTest
    static void fetchInventory_success() {
        Test.setMock(HttpCalloutMock.class, new InventoryMock(200, GOOD_INVENTORY));

        Test.startTest();
        List<MatrixApiService.InventoryItem> items = MatrixApiService.fetchInventory();
        Test.stopTest();

        System.assertEquals(2, items.size(), 'Should parse 2 inventory items');
        System.assertEquals('AS-001', items[0].adSpaceId);
        System.assertEquals('Univision Network', items[0].vehicleName);
    }

    @IsTest
    static void fetchInventory_emptyList() {
        Test.setMock(HttpCalloutMock.class, new InventoryMock(200, '{"inventory":[]}'));

        Test.startTest();
        List<MatrixApiService.InventoryItem> items = MatrixApiService.fetchInventory();
        Test.stopTest();

        System.assertEquals(0, items.size(), 'Should return empty list when API returns no items');
    }

    @IsTest
    static void fetchInventory_nullInventory() {
        Test.setMock(HttpCalloutMock.class, new InventoryMock(200, '{}'));

        Test.startTest();
        List<MatrixApiService.InventoryItem> items = MatrixApiService.fetchInventory();
        Test.stopTest();

        System.assertEquals(0, items.size(), 'Null inventory field should return empty list');
    }

    @IsTest
    static void fetchInventory_httpError_throws() {
        Test.setMock(HttpCalloutMock.class, new InventoryMock(503, 'Service Unavailable'));

        Test.startTest();
        try {
            MatrixApiService.fetchInventory();
            System.assert(false, 'Expected CalloutException');
        } catch (CalloutException e) {
            System.assert(e.getMessage().contains('503'), 'Exception should include status code');
        }
        Test.stopTest();
    }

    @IsTest
    static void createMediaPlan_success() {
        Test.setMock(HttpCalloutMock.class, new InventoryMock(201, GOOD_PLAN));

        Test.startTest();
        String planId = MatrixApiService.createMediaPlan('opp-123', new List<String>{'AS-001'});
        Test.stopTest();

        System.assertEquals('MP-99', planId, 'Should return the mediaPlanId from response');
    }

    @IsTest
    static void createMediaPlan_200AlsoAccepted() {
        Test.setMock(HttpCalloutMock.class, new InventoryMock(200, GOOD_PLAN));

        Test.startTest();
        String planId = MatrixApiService.createMediaPlan('opp-123', null);
        Test.stopTest();

        System.assertEquals('MP-99', planId);
    }

    @IsTest
    static void createMediaPlan_httpError_throws() {
        Test.setMock(HttpCalloutMock.class, new InventoryMock(400, '{"error":"bad request"}'));

        Test.startTest();
        try {
            MatrixApiService.createMediaPlan('opp-123', new List<String>());
            System.assert(false, 'Expected CalloutException');
        } catch (CalloutException e) {
            System.assert(e.getMessage().contains('400'), 'Exception should include status code');
        }
        Test.stopTest();
    }

    @IsTest
    static void createMediaPlan_blankPlanId_throws() {
        Test.setMock(HttpCalloutMock.class, new InventoryMock(200, '{"mediaPlanId":""}'));

        Test.startTest();
        try {
            MatrixApiService.createMediaPlan('opp-123', new List<String>());
            System.assert(false, 'Expected CalloutException for blank mediaPlanId');
        } catch (CalloutException e) {
            System.assert(e.getMessage().contains('mediaPlanId'), 'Exception should mention missing mediaPlanId');
        }
        Test.stopTest();
    }
}
