@IsTest
private class TrafficOrderServiceTest {

    // ── Shared test data ─────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Account advertiser = new Account(Name = 'Test Advertiser Co');
        insert advertiser;

        Opportunity opp = new Opportunity(
            Name       = 'Test Opp',
            AccountId  = advertiser.Id,
            StageName  = 'Approved',
            CloseDate  = Date.today().addDays(30)
        );
        insert opp;

        Advertising_Contract__c contract = new Advertising_Contract__c(
            Opportunity__c     = opp.Id,
            Account__c         = advertiser.Id,
            Contract_Status__c = 'Approved'
        );
        insert contract;

        Vehicle__c vehicle = new Vehicle__c(
            Name              = 'Test Vehicle',
            Vehicle_Code__c   = 'TST',
            Status__c         = 'Active'
        );
        insert vehicle;

        Budget_Line__c line = new Budget_Line__c(
            Opportunity__c             = opp.Id,
            Vehicle__c                 = vehicle.Id,
            Date_Type__c               = 'Broadcast',
            Broadcast_Date__c          = Date.today().addDays(7),
            Copy_Code__c               = 'COPY001',
            Copy_Rotation__c           = 'Even',
            Spot_Length__c             = ':30',
            Weekly_Spots__c            = 5,
            Spot_Rate__c               = 250.00
        );
        insert line;
    }

    // ── enqueueTransmission ──────────────────────────────────────────────────

    @IsTest
    static void enqueueTransmission_setsPendingAndEnqueuesJob() {
        Advertising_Contract__c contract = getContract();

        Test.startTest();
        TrafficOrderService.TransmitRequest req = new TrafficOrderService.TransmitRequest();
        req.contractId = contract.Id;
        TrafficOrderService.enqueueTransmission(new List<TrafficOrderService.TransmitRequest>{ req });
        Test.stopTest();

        Advertising_Contract__c updated = getContractById(contract.Id);
        Assert.areEqual('Pending', updated.Traffic_Status__c, 'Status should be Pending after enqueue');
        Assert.isNotNull(updated.Traffic_Callback_Token__c, 'Callback token should be populated');
        Assert.isNotNull(updated.Last_Traffic_Transmission__c, 'Last transmission timestamp should be set');
    }

    @IsTest
    static void enqueueTransmission_tokenIsThirtyTwoChars() {
        Advertising_Contract__c contract = getContract();

        Test.startTest();
        TrafficOrderService.TransmitRequest req = new TrafficOrderService.TransmitRequest();
        req.contractId = contract.Id;
        TrafficOrderService.enqueueTransmission(new List<TrafficOrderService.TransmitRequest>{ req });
        Test.stopTest();

        Advertising_Contract__c updated = getContractById(contract.Id);
        Assert.areEqual(32, updated.Traffic_Callback_Token__c.length(), 'Callback token should be 32 hex chars');
    }

    @IsTest
    static void enqueueTransmission_bulkTwoContracts() {
        Account advertiser2 = new Account(Name = 'Second Advertiser');
        insert advertiser2;

        Opportunity opp2 = new Opportunity(
            Name       = 'Second Test Opp',
            AccountId  = advertiser2.Id,
            StageName  = 'Approved',
            CloseDate  = Date.today().addDays(30)
        );
        insert opp2;

        Advertising_Contract__c contract2 = new Advertising_Contract__c(
            Opportunity__c     = opp2.Id,
            Account__c         = advertiser2.Id,
            Contract_Status__c = 'Approved'
        );
        insert contract2;

        Advertising_Contract__c contract1 = getContract();
        TrafficOrderService.TransmitRequest r1 = new TrafficOrderService.TransmitRequest();
        r1.contractId = contract1.Id;
        TrafficOrderService.TransmitRequest r2 = new TrafficOrderService.TransmitRequest();
        r2.contractId = contract2.Id;

        Test.startTest();
        TrafficOrderService.enqueueTransmission(
            new List<TrafficOrderService.TransmitRequest>{ r1, r2 }
        );
        Test.stopTest();

        List<Advertising_Contract__c> updated = [
            SELECT Traffic_Status__c FROM Advertising_Contract__c
            WHERE Id IN (:contract1.Id, :contract2.Id)
        ];
        for (Advertising_Contract__c c : updated) {
            Assert.areEqual('Pending', c.Traffic_Status__c, 'Both contracts should be Pending');
        }
    }

    // ── generateCallbackToken ─────────────────────────────────────────────────

    @IsTest
    static void generateCallbackToken_producesUniqueValues() {
        String t1 = TrafficOrderService.generateCallbackToken();
        String t2 = TrafficOrderService.generateCallbackToken();
        Assert.areNotEqual(t1, t2, 'Each generated token should be unique');
    }

    // ── Queueable — success path ─────────────────────────────────────────────

    @IsTest
    static void queueable_successResponseSetsTransmitted() {
        Advertising_Contract__c contract = prepareActiveContract();
        Test.setMock(HttpCalloutMock.class, new TrafficMockSuccess('WO-99001'));

        Test.startTest();
        new TrafficOrderTransmitQueueable(contract.Id).execute(null);
        Test.stopTest();

        Advertising_Contract__c updated = getContractById(contract.Id);
        Assert.areEqual('Transmitted', updated.Traffic_Status__c);
        Assert.areEqual('WO-99001', updated.Traffic_Order_ID__c);
        Assert.isNull(updated.Traffic_Error_Message__c);
        Assert.isNotNull(updated.Last_Traffic_Transmission__c);
    }

    @IsTest
    static void queueable_http201AlsoSetsTransmitted() {
        Advertising_Contract__c contract = prepareActiveContract();
        Test.setMock(HttpCalloutMock.class, new TrafficMockSuccess('WO-99002', 201));

        Test.startTest();
        new TrafficOrderTransmitQueueable(contract.Id).execute(null);
        Test.stopTest();

        Assert.areEqual('Transmitted', getContractById(contract.Id).Traffic_Status__c);
    }

    // ── Queueable — error paths ──────────────────────────────────────────────

    @IsTest
    static void queueable_http400SetsRejected() {
        Advertising_Contract__c contract = prepareActiveContract();
        Test.setMock(HttpCalloutMock.class, new TrafficMockError(400, 'Bad payload'));

        Test.startTest();
        new TrafficOrderTransmitQueueable(contract.Id).execute(null);
        Test.stopTest();

        Advertising_Contract__c updated = getContractById(contract.Id);
        Assert.areEqual('Rejected', updated.Traffic_Status__c);
        Assert.isTrue(updated.Traffic_Error_Message__c.contains('400'));
    }

    @IsTest
    static void queueable_http500SetsRejected() {
        Advertising_Contract__c contract = prepareActiveContract();
        Test.setMock(HttpCalloutMock.class, new TrafficMockError(500, 'Internal server error'));

        Test.startTest();
        new TrafficOrderTransmitQueueable(contract.Id).execute(null);
        Test.stopTest();

        Assert.areEqual('Rejected', getContractById(contract.Id).Traffic_Status__c);
    }

    @IsTest
    static void queueable_networkExceptionSetsRejected() {
        Advertising_Contract__c contract = prepareActiveContract();
        Test.setMock(HttpCalloutMock.class, new TrafficMockException());

        Test.startTest();
        new TrafficOrderTransmitQueueable(contract.Id).execute(null);
        Test.stopTest();

        Advertising_Contract__c updated = getContractById(contract.Id);
        Assert.areEqual('Rejected', updated.Traffic_Status__c);
        Assert.isNotNull(updated.Traffic_Error_Message__c);
    }

    @IsTest
    static void queueable_noSpotsStillTransmits() {
        // Contract with opportunity that has no budget lines
        Account acct = new Account(Name = 'No Spots Advertiser');
        insert acct;
        Opportunity opp = new Opportunity(
            Name      = 'No Spots Opp',
            AccountId = acct.Id,
            StageName = 'Approved',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        Advertising_Contract__c contract = new Advertising_Contract__c(
            Opportunity__c             = opp.Id,
            Account__c                 = acct.Id,
            Contract_Status__c         = 'Active',
            Traffic_Callback_Token__c  = 'testtoken00000000000000000000001'
        );
        insert contract;

        Test.setMock(HttpCalloutMock.class, new TrafficMockSuccess('WO-99003'));

        Test.startTest();
        new TrafficOrderTransmitQueueable(contract.Id).execute(null);
        Test.stopTest();

        Assert.areEqual('Transmitted', getContractById(contract.Id).Traffic_Status__c);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Advertising_Contract__c getContract() {
        return [SELECT Id, Opportunity__c FROM Advertising_Contract__c LIMIT 1];
    }

    private static Advertising_Contract__c getContractById(Id contractId) {
        return [
            SELECT Traffic_Status__c, Traffic_Order_ID__c, Traffic_Error_Message__c,
                   Traffic_Callback_Token__c, Last_Traffic_Transmission__c
            FROM Advertising_Contract__c
            WHERE Id = :contractId
            LIMIT 1
        ];
    }

    private static Advertising_Contract__c prepareActiveContract() {
        Advertising_Contract__c contract = getContract();
        contract.Contract_Status__c       = 'Active';
        contract.Traffic_Callback_Token__c = 'activetesttoken0000000000000001';
        update contract;
        return contract;
    }

    // ── HTTP Mocks ────────────────────────────────────────────────────────────

    private class TrafficMockSuccess implements HttpCalloutMock {
        private String orderId;
        private Integer statusCode;

        TrafficMockSuccess(String orderId) { this(orderId, 200); }
        TrafficMockSuccess(String orderId, Integer statusCode) {
            this.orderId    = orderId;
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setStatus('OK');
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"orderId":"' + orderId + '","status":"ACCEPTED"}');
            return res;
        }
    }

    private class TrafficMockError implements HttpCalloutMock {
        private Integer statusCode;
        private String  errorBody;

        TrafficMockError(Integer statusCode, String errorBody) {
            this.statusCode = statusCode;
            this.errorBody  = errorBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setStatus('Error');
            res.setBody('{"error":"' + errorBody + '"}');
            return res;
        }
    }

    private class TrafficMockException implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated network failure');
        }
    }
}
