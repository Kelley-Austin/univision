@IsTest
private class MatrixPromoteToContractActionTest {

    private class PlanMock implements HttpCalloutMock {
        private final Integer code;
        private final String body;
        PlanMock(Integer code, String body) { this.code = code; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setBody(body);
            return res;
        }
    }

    @TestSetup
    static void setup() {
        insert new Advertising_Opportunity__c();
    }

    @IsTest
    static void registerMediaPlan_success_storesIdOnOpportunity() {
        Advertising_Opportunity__c opp = [SELECT Id FROM Advertising_Opportunity__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new PlanMock(201, '{"mediaPlanId":"MP-42"}'));

        MatrixPromoteToContractAction.Request req = new MatrixPromoteToContractAction.Request();
        req.opportunityId = opp.Id;
        req.adSpaceIdsCsv = 'AS-001, AS-002';

        Test.startTest();
        List<MatrixPromoteToContractAction.Result> results =
            MatrixPromoteToContractAction.registerMediaPlan(new List<MatrixPromoteToContractAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals('MP-42', results[0].mediaPlanId);

        Advertising_Opportunity__c updated = [SELECT Media_Cloud_Media_Plan_ID__c FROM Advertising_Opportunity__c WHERE Id = :opp.Id];
        System.assertEquals('MP-42', updated.Media_Cloud_Media_Plan_ID__c, 'Plan ID should be persisted on the opportunity');
    }

    @IsTest
    static void registerMediaPlan_noAdSpaces_stillSucceeds() {
        Advertising_Opportunity__c opp = [SELECT Id FROM Advertising_Opportunity__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new PlanMock(200, '{"mediaPlanId":"MP-99"}'));

        MatrixPromoteToContractAction.Request req = new MatrixPromoteToContractAction.Request();
        req.opportunityId = opp.Id;

        Test.startTest();
        List<MatrixPromoteToContractAction.Result> results =
            MatrixPromoteToContractAction.registerMediaPlan(new List<MatrixPromoteToContractAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals('MP-99', results[0].mediaPlanId);
    }

    @IsTest
    static void registerMediaPlan_apiError_returnsFailureResult() {
        Advertising_Opportunity__c opp = [SELECT Id FROM Advertising_Opportunity__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new PlanMock(500, 'Server Error'));

        MatrixPromoteToContractAction.Request req = new MatrixPromoteToContractAction.Request();
        req.opportunityId = opp.Id;

        Test.startTest();
        List<MatrixPromoteToContractAction.Result> results =
            MatrixPromoteToContractAction.registerMediaPlan(new List<MatrixPromoteToContractAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(String.isNotBlank(results[0].errorMessage), 'Error message should be populated');

        Advertising_Opportunity__c unchanged = [SELECT Media_Cloud_Media_Plan_ID__c FROM Advertising_Opportunity__c WHERE Id = :opp.Id];
        System.assertEquals(null, unchanged.Media_Cloud_Media_Plan_ID__c, 'Plan ID should NOT be set on failure');
    }

    @IsTest
    static void registerMediaPlan_bulkRequests_processedIndependently() {
        insert new Advertising_Opportunity__c();
        List<Advertising_Opportunity__c> opps = [SELECT Id FROM Advertising_Opportunity__c LIMIT 2];
        Test.setMock(HttpCalloutMock.class, new PlanMock(201, '{"mediaPlanId":"MP-BULK"}'));

        List<MatrixPromoteToContractAction.Request> requests = new List<MatrixPromoteToContractAction.Request>();
        for (Advertising_Opportunity__c opp : opps) {
            MatrixPromoteToContractAction.Request req = new MatrixPromoteToContractAction.Request();
            req.opportunityId = opp.Id;
            requests.add(req);
        }

        Test.startTest();
        List<MatrixPromoteToContractAction.Result> results =
            MatrixPromoteToContractAction.registerMediaPlan(requests);
        Test.stopTest();

        System.assertEquals(2, results.size());
        for (MatrixPromoteToContractAction.Result res : results) {
            System.assertEquals(true, res.success);
        }
    }
}
