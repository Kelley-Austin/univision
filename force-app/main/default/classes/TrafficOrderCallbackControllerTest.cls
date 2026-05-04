@IsTest
private class TrafficOrderCallbackControllerTest {

    @TestSetup
    static void setupData() {
        Account acct = new Account(Name = 'Test Advertiser');
        insert acct;

        Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
            Account__c = acct.Id,
            Status__c = 'Active'
        );
        insert opp;

        Advertising_Contract__c contract = new Advertising_Contract__c(
            Advertising_Opportunity__c = opp.Id,
            Contract_Status__c = 'Active',
            Traffic_Status__c = 'Pending',
            Traffic_Order_ID__c = 'TRF-CALLBACK-001'
        );
        insert contract;
    }

    private static void setRestContext(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/traffic/callback';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    @IsTest
    static void testConfirmedCallbackByContractId() {
        Advertising_Contract__c contract = [SELECT Id FROM Advertising_Contract__c LIMIT 1];

        setRestContext(JSON.serialize(new Map<String, Object>{
            'contractId'     => contract.Id,
            'trafficOrderId' => 'TRF-CALLBACK-001',
            'status'         => 'Confirmed',
            'message'        => ''
        }));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Advertising_Contract__c updated = [
            SELECT Traffic_Status__c, Traffic_Order_ID__c
            FROM Advertising_Contract__c WHERE Id = :contract.Id
        ];
        Assert.areEqual('Confirmed', updated.Traffic_Status__c);
        Assert.areEqual('TRF-CALLBACK-001', updated.Traffic_Order_ID__c);
    }

    @IsTest
    static void testConfirmedCallbackByTrafficOrderId() {
        setRestContext(JSON.serialize(new Map<String, Object>{
            'trafficOrderId' => 'TRF-CALLBACK-001',
            'status'         => 'Confirmed',
            'message'        => ''
        }));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Advertising_Contract__c updated = [
            SELECT Traffic_Status__c FROM Advertising_Contract__c LIMIT 1
        ];
        Assert.areEqual('Confirmed', updated.Traffic_Status__c);
    }

    @IsTest
    static void testErrorCallbackSetsErrorStatusAndMessage() {
        Advertising_Contract__c contract = [SELECT Id FROM Advertising_Contract__c LIMIT 1];

        setRestContext(JSON.serialize(new Map<String, Object>{
            'contractId'     => contract.Id,
            'trafficOrderId' => 'TRF-CALLBACK-001',
            'status'         => 'Error',
            'message'        => 'Copy code not found in traffic system.'
        }));

        Test.startTest();
        TrafficOrderCallbackController.handleCallback();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Advertising_Contract__c updated = [
            SELECT Traffic_Status__c, Traffic_Error_Message__c
            FROM Advertising_Contract__c WHERE Id = :contract.Id
        ];
        Assert.areEqual('Error', updated.Traffic_Status__c);
        Assert.areEqual('Copy code not found in traffic system.', updated.Traffic_Error_Message__c);
    }

    @IsTest
    static void testMissingStatusReturns400() {
        Advertising_Contract__c contract = [SELECT Id FROM Advertising_Contract__c LIMIT 1];

        setRestContext(JSON.serialize(new Map<String, Object>{
            'contractId' => contract.Id
        }));

        TrafficOrderCallbackController.handleCallback();

        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void testInvalidStatusReturns400() {
        Advertising_Contract__c contract = [SELECT Id FROM Advertising_Contract__c LIMIT 1];

        setRestContext(JSON.serialize(new Map<String, Object>{
            'contractId' => contract.Id,
            'status'     => 'Processing'
        }));

        TrafficOrderCallbackController.handleCallback();

        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void testContractNotFoundReturns404() {
        setRestContext(JSON.serialize(new Map<String, Object>{
            'trafficOrderId' => 'TRF-DOES-NOT-EXIST',
            'status'         => 'Confirmed'
        }));

        TrafficOrderCallbackController.handleCallback();

        Assert.areEqual(404, RestContext.response.statusCode);
    }

    @IsTest
    static void testMissingIdentifiersReturns404() {
        setRestContext(JSON.serialize(new Map<String, Object>{
            'status' => 'Confirmed'
        }));

        TrafficOrderCallbackController.handleCallback();

        Assert.areEqual(404, RestContext.response.statusCode);
    }
}
