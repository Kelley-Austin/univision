public without sharing class TrafficOrderTransmitQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> budgetLineIds;

    // Configure via Setup → Named Credentials → Traffic_System
    @TestVisible
    private static final String TRAFFIC_ENDPOINT = 'callout:Traffic_System/api/traffic/orders';

    public TrafficOrderTransmitQueueable(List<Id> budgetLineIds) {
        this.budgetLineIds = budgetLineIds;
    }

    public void execute(QueueableContext ctx) {
        List<Budget_Line__c> lines = [
            SELECT Id, Name, Copy_Code__c, Copy_Rotation__c, Spot_Length__c,
                   Weekly_Spots__c, Spot_Rate__c, Spot_Instructions__c,
                   Opportunity__c
            FROM Budget_Line__c
            WHERE Id IN :budgetLineIds
        ];

        if (lines.isEmpty()) {
            return;
        }

        // Collect opportunity IDs for a single contract lookup after all callouts
        Set<Id> oppIds = new Set<Id>();
        for (Budget_Line__c line : lines) {
            if (line.Opportunity__c != null) {
                oppIds.add(line.Opportunity__c);
            }
        }

        Map<Id, Advertising_Contract__c> contractByOpp = queryContractsByOpp(oppIds);

        // Perform all callouts first, collect results, then do DML
        List<Budget_Line__c> lineUpdates = new List<Budget_Line__c>();
        Map<Id, Advertising_Contract__c> contractUpdates = new Map<Id, Advertising_Contract__c>();

        for (Budget_Line__c line : lines) {
            TransmitResult result = callout(line);

            Budget_Line__c lu = new Budget_Line__c(Id = line.Id);
            if (result.trafficOrderId != null) {
                lu.Traffic_Order_ID__c = result.trafficOrderId;
            }
            if (result.errorMessage != null) {
                lu.Traffic_Status__c = 'Error';
                lu.Traffic_Error_Message__c = result.errorMessage;
            }
            lineUpdates.add(lu);

            if (line.Opportunity__c != null
                    && contractByOpp.containsKey(line.Opportunity__c)) {
                Advertising_Contract__c c = contractByOpp.get(line.Opportunity__c);
                if (result.trafficOrderId != null) {
                    c.Traffic_Order_ID__c = result.trafficOrderId;
                }
                if (result.errorMessage != null) {
                    c.Traffic_Status__c = 'Error';
                    c.Traffic_Error_Message__c = result.errorMessage;
                }
                contractUpdates.put(c.Id, c);
            }
        }

        if (!lineUpdates.isEmpty()) {
            update lineUpdates;
        }
        if (!contractUpdates.isEmpty()) {
            update contractUpdates.values();
        }
    }

    private TransmitResult callout(Budget_Line__c line) {
        TransmitResult result = new TransmitResult();

        Map<String, Object> payload = new Map<String, Object>{
            'budgetLineId'      => line.Id,
            'budgetLineName'    => line.Name,
            'copyCode'          => line.Copy_Code__c,
            'copyRotation'      => line.Copy_Rotation__c,
            'spotLength'        => line.Spot_Length__c,
            'weeklySpots'       => line.Weekly_Spots__c,
            'spotRate'          => line.Spot_Rate__c,
            'spotInstructions'  => line.Spot_Instructions__c
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(TRAFFIC_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(10000);

        try {
            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> body =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                result.trafficOrderId = (String) body.get('trafficOrderId');
            } else {
                result.errorMessage =
                    'Traffic system returned HTTP ' + res.getStatusCode() + ': ' + res.getBody();
            }
        } catch (Exception e) {
            result.errorMessage = 'Callout failed: ' + e.getMessage();
        }

        return result;
    }

    private Map<Id, Advertising_Contract__c> queryContractsByOpp(Set<Id> oppIds) {
        Map<Id, Advertising_Contract__c> result = new Map<Id, Advertising_Contract__c>();
        if (oppIds.isEmpty()) {
            return result;
        }
        for (Advertising_Contract__c c : [
            SELECT Id, Opportunity__c,
                   Traffic_Status__c, Traffic_Order_ID__c, Traffic_Error_Message__c
            FROM Advertising_Contract__c
            WHERE Opportunity__c IN :oppIds
            AND Contract_Status__c NOT IN ('Cancelled', 'Completed')
            ORDER BY CreatedDate DESC
        ]) {
            if (!result.containsKey(c.Opportunity__c)) {
                result.put(c.Opportunity__c, c);
            }
        }
        return result;
    }

    private class TransmitResult {
        String trafficOrderId;
        String errorMessage;
    }
}
