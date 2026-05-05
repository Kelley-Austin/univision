@RestResource(urlMapping='/traffic/callback/*')
global without sharing class TrafficOrderCallbackController {

    global class CallbackPayload {
        global String trafficOrderId;
        global String contractId;
        global String status;
        global String message;
    }

    @HttpPost
    global static void handleCallback() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            CallbackPayload payload = (CallbackPayload) JSON.deserialize(
                req.requestBody.toString(), CallbackPayload.class
            );

            if (String.isBlank(payload.status)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('{"error":"status is required"}');
                return;
            }

            if (payload.status != 'Confirmed' && payload.status != 'Error') {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('{"error":"status must be Confirmed or Error"}');
                return;
            }

            Advertising_Contract__c contract = findContract(payload);

            if (contract == null) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf('{"error":"Contract not found"}');
                return;
            }

            contract.Traffic_Status__c = payload.status;
            if (String.isNotBlank(payload.trafficOrderId)) {
                contract.Traffic_Order_ID__c = payload.trafficOrderId;
            }
            if (String.isNotBlank(payload.message)) {
                contract.Traffic_Error_Message__c = payload.message;
            }

            update contract;

            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"result":"ok","contractId":"' + contract.Id + '"}');

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(
                '{"error":"' + e.getMessage().replace('"', '\'') + '"}'
            );
        }
    }

    private static Advertising_Contract__c findContract(CallbackPayload payload) {
        if (String.isNotBlank(payload.contractId)) {
            List<Advertising_Contract__c> contracts = [
                SELECT Id, Traffic_Status__c, Traffic_Order_ID__c, Traffic_Error_Message__c
                FROM Advertising_Contract__c
                WHERE Id = :payload.contractId
                LIMIT 1
            ];
            return contracts.isEmpty() ? null : contracts[0];
        }

        if (String.isNotBlank(payload.trafficOrderId)) {
            List<Advertising_Contract__c> contracts = [
                SELECT Id, Traffic_Status__c, Traffic_Order_ID__c, Traffic_Error_Message__c
                FROM Advertising_Contract__c
                WHERE Traffic_Order_ID__c = :payload.trafficOrderId
                LIMIT 1
            ];
            return contracts.isEmpty() ? null : contracts[0];
        }

        return null;
    }
}
