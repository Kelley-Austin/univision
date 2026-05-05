@IsTest
private class TrafficOrderTransmitQueueableTest {

    @TestSetup
    static void setupData() {
        Account acct = new Account(Name = 'Test Advertiser');
        insert acct;

        Opportunity opp = new Opportunity(
            Name       = 'Test Opp',
            AccountId  = acct.Id,
            StageName  = 'Active',
            CloseDate  = Date.today().addDays(30)
        );
        insert opp;

        Advertising_Contract__c contract = new Advertising_Contract__c(
            Opportunity__c = opp.Id,
            Contract_Status__c = 'Active',
            Traffic_Status__c = 'Pending'
        );
        insert contract;

        Channel__c channel = new Channel__c(
            Name = 'Test Channel',
            Channel_Code__c = 'TC-002'
        );
        insert channel;

        Budget_Line__c line = new Budget_Line__c(
            Opportunity__c = opp.Id,
            Channel__c = channel.Id,
            Account__c = acct.Id,
            Status__c = 'Draft',
            Traffic_Status__c = 'Pending',
            Copy_Code__c = 'CP-Q001',
            Spot_Length__c = ':30',
            Weekly_Spots__c = 3,
            Spot_Rate__c = 2000
        );
        insert line;
    }

    // Mock that simulates a successful traffic system acknowledgment
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"trafficOrderId":"TRF-TEST-001"}');
            return res;
        }
    }

    // Mock that simulates a server-side failure
    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    @IsTest
    static void testSuccessfulTransmitSetsOrderId() {
        Budget_Line__c line = [SELECT Id FROM Budget_Line__c LIMIT 1];
        Advertising_Contract__c contract = [SELECT Id FROM Advertising_Contract__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        System.enqueueJob(new TrafficOrderTransmitQueueable(new List<Id>{ line.Id }));
        Test.stopTest();

        Budget_Line__c updatedLine = [
            SELECT Traffic_Status__c, Traffic_Order_ID__c, Traffic_Error_Message__c
            FROM Budget_Line__c WHERE Id = :line.Id
        ];
        // Status stays Pending — callback is responsible for Confirmed
        Assert.areEqual('Pending', updatedLine.Traffic_Status__c);
        Assert.areEqual('TRF-TEST-001', updatedLine.Traffic_Order_ID__c);
        Assert.isNull(updatedLine.Traffic_Error_Message__c);

        Advertising_Contract__c updatedContract = [
            SELECT Traffic_Order_ID__c, Traffic_Status__c
            FROM Advertising_Contract__c WHERE Id = :contract.Id
        ];
        Assert.areEqual('TRF-TEST-001', updatedContract.Traffic_Order_ID__c);
        Assert.areEqual('Pending', updatedContract.Traffic_Status__c);
    }

    @IsTest
    static void testHttpErrorSetsErrorStatus() {
        Budget_Line__c line = [SELECT Id FROM Budget_Line__c LIMIT 1];
        Advertising_Contract__c contract = [SELECT Id FROM Advertising_Contract__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        System.enqueueJob(new TrafficOrderTransmitQueueable(new List<Id>{ line.Id }));
        Test.stopTest();

        Budget_Line__c updatedLine = [
            SELECT Traffic_Status__c, Traffic_Error_Message__c
            FROM Budget_Line__c WHERE Id = :line.Id
        ];
        Assert.areEqual('Error', updatedLine.Traffic_Status__c);
        Assert.isTrue(
            updatedLine.Traffic_Error_Message__c.contains('500'),
            'Error message should reference HTTP 500'
        );

        Advertising_Contract__c updatedContract = [
            SELECT Traffic_Status__c FROM Advertising_Contract__c WHERE Id = :contract.Id
        ];
        Assert.areEqual('Error', updatedContract.Traffic_Status__c);
    }

    @IsTest
    static void testEmptyIdListDoesNothing() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        System.enqueueJob(new TrafficOrderTransmitQueueable(new List<Id>()));
        Test.stopTest();

        // Should complete without exception; no records changed
        Budget_Line__c line = [SELECT Traffic_Status__c FROM Budget_Line__c LIMIT 1];
        Assert.areEqual('Pending', line.Traffic_Status__c);
    }
}
