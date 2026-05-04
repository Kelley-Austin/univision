public with sharing class MatrixInventoryApiService {

    private static final String DEFAULT_CREDENTIAL = 'Matrix_API';

    public class InventoryItem {
        public String adSpaceId;
        public String vehicleName;
        public String status;
    }

    public class InventoryResponse {
        public List<InventoryItem> inventory;
    }

    public class MediaPlanRequest {
        public String opportunityId;
        public List<String> adSpaceIds;
    }

    public class MediaPlanResponse {
        public String mediaPlanId;
    }

    private static String resolveCredential() {
        List<Matrix_Sync_Config__mdt> cfg = [
            SELECT Named_Credential__c FROM Matrix_Sync_Config__mdt
            WHERE DeveloperName = 'Default' LIMIT 1
        ];
        return (!cfg.isEmpty() && String.isNotBlank(cfg[0].Named_Credential__c))
            ? cfg[0].Named_Credential__c
            : DEFAULT_CREDENTIAL;
    }

    public static List<InventoryItem> fetchInventory() {
        String cred = resolveCredential();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + cred + '/inventory');
        req.setMethod('GET');
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new CalloutException(
                'Matrix API /inventory returned HTTP ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        InventoryResponse parsed = (InventoryResponse) JSON.deserialize(res.getBody(), InventoryResponse.class);
        return parsed.inventory != null ? parsed.inventory : new List<InventoryItem>();
    }

    public static String createMediaPlan(String opportunityId, List<String> adSpaceIds) {
        String cred = resolveCredential();
        MediaPlanRequest payload = new MediaPlanRequest();
        payload.opportunityId = opportunityId;
        payload.adSpaceIds = adSpaceIds != null ? adSpaceIds : new List<String>();

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + cred + '/plans');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new CalloutException(
                'Matrix API /plans returned HTTP ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        MediaPlanResponse parsed = (MediaPlanResponse) JSON.deserialize(res.getBody(), MediaPlanResponse.class);
        if (String.isBlank(parsed.mediaPlanId)) {
            throw new CalloutException('Matrix API /plans response did not contain a mediaPlanId.');
        }
        return parsed.mediaPlanId;
    }
}
