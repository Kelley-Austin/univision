@IsTest
private class TrafficOrderCallbackControllerTest {

    private static final String VALID_TOKEN  = 'validtoken00000000000000000001x';
    private static final String VALID_ORDER  = 'CNT-000001';
    private static final String TRAFFIC_ID   = 'WO-55555';

    // ── Shared test data ─────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Account acct = new Account(Name = 'Callback Test Advertiser');
        insert acct;

        Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
            Account__c = acct.Id,
            Status__c  = 'Approved'
        );
        insert opp;

        // Note: Name is AutoNumber so we query it back after insert
        Advertising_Contract__c contract = new Advertising_Contract__c(
            Advertising_Opportunity__c  = opp.Id,
            Account__c                  = acct.Id,
            Contract_Status__c          = 'Active',
            Traffic_Status__c           = 'Transmitted',
            Traffic_Callback_Token__c   = VALID_TOKEN,
            Make_Good_Credits__c        = 0
        );
        insert contract;
    }

    // ── ACCEPTED callback ────────────────────────────────────────────────────

    @IsTest
    static void handleCallback_acceptedUpdatesStatus() {
        Advertising_Contract__c contract = getContract();
        setupRestContext(buildPayload(contract.Name, 'ACCEPTED', VALID_TOKEN, TRAFFIC_ID, null, null));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Advertising_Contract__c updated = getContractById(contract.Id);
        Assert.areEqual(200, RestContext.response.statusCode);
        Assert.areEqual('Accepted', updated.Traffic_Status__c);
        Assert.areEqual(TRAFFIC_ID, updated.Traffic_Order_ID__c);
        Assert.isNull(updated.Traffic_Error_Message__c, 'No error message on accepted');
    }

    // ── REJECTED callback ────────────────────────────────────────────────────

    @IsTest
    static void handleCallback_rejectedUpdatesStatusAndError() {
        Advertising_Contract__c contract = getContract();
        setupRestContext(buildPayload(contract.Name, 'REJECTED', VALID_TOKEN, null,
                                     'Missing creative material', null));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Advertising_Contract__c updated = getContractById(contract.Id);
        Assert.areEqual('Rejected', updated.Traffic_Status__c);
        Assert.areEqual('Missing creative material', updated.Traffic_Error_Message__c);
    }

    // ── MAKE_GOOD callback ───────────────────────────────────────────────────

    @IsTest
    static void handleCallback_makeGoodAddsCredits() {
        Advertising_Contract__c contract = getContract();
        setupRestContext(buildPayload(contract.Name, 'MAKE_GOOD', VALID_TOKEN, null, null, 750.00));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Advertising_Contract__c updated = getContractById(contract.Id);
        Assert.areEqual('Make-Good Required', updated.Traffic_Status__c);
        Assert.areEqual(750.00, updated.Make_Good_Credits__c, 'Make-good credits should be added');
    }

    @IsTest
    static void handleCallback_makeGoodAccumulatesCredits() {
        Advertising_Contract__c contract = getContract();
        // First make-good
        setupRestContext(buildPayload(contract.Name, 'MAKE_GOOD', VALID_TOKEN, null, null, 250.00));
        TrafficOrderCallbackController.handleCallback();

        // Second make-good — re-setup RestContext
        setupRestContext(buildPayload(contract.Name, 'MAKE_GOOD', VALID_TOKEN, null, null, 500.00));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Advertising_Contract__c updated = getContractById(contract.Id);
        Assert.areEqual(750.00, updated.Make_Good_Credits__c, 'Credits should accumulate across callbacks');
    }

    // ── COMPLETED callback ───────────────────────────────────────────────────

    @IsTest
    static void handleCallback_completedSetsStatus() {
        Advertising_Contract__c contract = getContract();
        setupRestContext(buildPayload(contract.Name, 'COMPLETED', VALID_TOKEN, TRAFFIC_ID, null, null));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Assert.areEqual('Completed', getContractById(contract.Id).Traffic_Status__c);
    }

    // ── Security: invalid token ──────────────────────────────────────────────

    @IsTest
    static void handleCallback_invalidTokenReturns401() {
        Advertising_Contract__c contract = getContract();
        setupRestContext(buildPayload(contract.Name, 'ACCEPTED', 'wrongtoken000000000000000000001', null, null, null));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Assert.areEqual(401, RestContext.response.statusCode);
        // Status should not have changed
        Assert.areEqual('Transmitted', getContractById(contract.Id).Traffic_Status__c);
    }

    // ── Security: unknown order ──────────────────────────────────────────────

    @IsTest
    static void handleCallback_unknownOrderReturns404() {
        setupRestContext(buildPayload('CNT-XXXXXX', 'ACCEPTED', VALID_TOKEN, null, null, null));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Assert.areEqual(404, RestContext.response.statusCode);
    }

    // ── Validation: missing required fields ──────────────────────────────────

    @IsTest
    static void handleCallback_missingOrderIdReturns400() {
        setupRestContext('{"status":"ACCEPTED","callbackToken":"' + VALID_TOKEN + '"}');

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void handleCallback_malformedJsonReturns500() {
        setupRestContext('NOT_JSON_AT_ALL');

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Assert.areEqual(500, RestContext.response.statusCode);
    }

    // ── Unknown traffic status maps gracefully ───────────────────────────────

    @IsTest
    static void handleCallback_unknownStatusFallsBackToTransmitted() {
        Advertising_Contract__c contract = getContract();
        setupRestContext(buildPayload(contract.Name, 'PENDING_REVIEW', VALID_TOKEN, null, null, null));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Assert.areEqual('Transmitted', getContractById(contract.Id).Traffic_Status__c);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Advertising_Contract__c getContract() {
        return [
            SELECT Id, Name, Traffic_Status__c, Traffic_Callback_Token__c
            FROM Advertising_Contract__c
            LIMIT 1
        ];
    }

    private static Advertising_Contract__c getContractById(Id contractId) {
        return [
            SELECT Traffic_Status__c, Traffic_Order_ID__c, Traffic_Error_Message__c,
                   Make_Good_Credits__c
            FROM Advertising_Contract__c
            WHERE Id = :contractId
            LIMIT 1
        ];
    }

    private static void setupRestContext(String body) {
        RestRequest req  = new RestRequest();
        req.requestURI   = '/services/apexrest/traffic/callback/';
        req.httpMethod   = 'POST';
        req.requestBody  = Blob.valueOf(body);

        RestResponse res = new RestResponse();

        RestContext.request  = req;
        RestContext.response = res;
    }

    private static String buildPayload(
        String orderId,
        String status,
        String token,
        String trafficOrderId,
        String errorMessage,
        Decimal makeGoodCredits
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'orderId'       => orderId,
            'status'        => status,
            'callbackToken' => token
        };
        if (trafficOrderId != null)   payload.put('trafficOrderId', trafficOrderId);
        if (errorMessage != null)     payload.put('errorMessage', errorMessage);
        if (makeGoodCredits != null)  payload.put('makeGoodCredits', makeGoodCredits);
        return JSON.serialize(payload);
    }
}
