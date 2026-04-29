/**
 * REST endpoint that receives inbound status callbacks from the traffic system.
 * The traffic system POSTs here after accepting, rejecting, or flagging a make-good
 * on an order it received from TrafficOrderTransmitQueueable.
 *
 * URL: /services/apexrest/traffic/callback/
 *
 * Expected JSON body:
 * {
 *   "orderId":        "CNT-000001",          // Advertising_Contract__c.Name
 *   "trafficOrderId": "WO-98765",            // ID in the traffic system
 *   "status":         "ACCEPTED",            // ACCEPTED | REJECTED | MAKE_GOOD | COMPLETED
 *   "callbackToken":  "abc123...",           // Must match Traffic_Callback_Token__c
 *   "errorMessage":   "...",                 // Optional, present on REJECTED
 *   "makeGoodCredits": 500.00               // Optional, present on MAKE_GOOD
 * }
 */
@RestResource(urlMapping='/traffic/callback/*')
global with sharing class TrafficOrderCallbackController {

    private static final Map<String, String> STATUS_MAP = new Map<String, String>{
        'ACCEPTED'   => 'Accepted',
        'REJECTED'   => 'Rejected',
        'MAKE_GOOD'  => 'Make-Good Required',
        'COMPLETED'  => 'Completed'
    };

    @HttpPost
    global static void handleCallback() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            Map<String, Object> payload = parsePayload();

            String orderId       = (String) payload.get('orderId');
            String trafficStatus = (String) payload.get('status');
            String trafficOrdId  = (String) payload.get('trafficOrderId');
            String token         = (String) payload.get('callbackToken');
            String errMsg        = (String) payload.get('errorMessage');
            Decimal mgCredits    = payload.containsKey('makeGoodCredits')
                                        ? (Decimal) payload.get('makeGoodCredits') : null;

            if (String.isBlank(orderId) || String.isBlank(trafficStatus) || String.isBlank(token)) {
                respond(res, 400, '{"error":"Missing required fields: orderId, status, callbackToken"}');
                return;
            }

            List<Advertising_Contract__c> contracts = [
                SELECT Id, Traffic_Callback_Token__c, Make_Good_Credits__c
                FROM Advertising_Contract__c
                WHERE Name = :orderId
                LIMIT 1
            ];

            if (contracts.isEmpty()) {
                respond(res, 404, '{"error":"Order not found"}');
                return;
            }

            Advertising_Contract__c contract = contracts[0];

            // Constant-time token comparison to prevent timing attacks
            if (!tokensMatch(contract.Traffic_Callback_Token__c, token)) {
                respond(res, 401, '{"error":"Invalid callback token"}');
                return;
            }

            Advertising_Contract__c toUpdate = new Advertising_Contract__c(Id = contract.Id);
            toUpdate.Traffic_Status__c = STATUS_MAP.containsKey(trafficStatus)
                                              ? STATUS_MAP.get(trafficStatus) : 'Transmitted';

            if (String.isNotBlank(trafficOrdId)) {
                toUpdate.Traffic_Order_ID__c = trafficOrdId;
            }
            if (String.isNotBlank(errMsg)) {
                toUpdate.Traffic_Error_Message__c = errMsg;
            } else if (toUpdate.Traffic_Status__c == 'Accepted') {
                toUpdate.Traffic_Error_Message__c = null;
            }
            if (mgCredits != null && mgCredits > 0) {
                Decimal existing = contract.Make_Good_Credits__c != null ? contract.Make_Good_Credits__c : 0;
                toUpdate.Make_Good_Credits__c = existing + mgCredits;
            }

            update toUpdate;
            respond(res, 200, '{"result":"success"}');

        } catch (Exception e) {
            respond(res, 500, '{"error":"' + e.getMessage().replace('"', '\\"') + '"}');
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private static Map<String, Object> parsePayload() {
        String body = RestContext.request.requestBody.toString();
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    private static Boolean tokensMatch(String stored, String received) {
        if (String.isBlank(stored) || String.isBlank(received)) return false;
        // XOR each character so both branches do equal work (constant-time)
        if (stored.length() != received.length()) return false;
        Integer diff = 0;
        for (Integer i = 0; i < stored.length(); i++) {
            diff |= stored.charAt(i) ^ received.charAt(i);
        }
        return diff == 0;
    }

    private static void respond(RestResponse res, Integer statusCode, String body) {
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(body);
    }
}
