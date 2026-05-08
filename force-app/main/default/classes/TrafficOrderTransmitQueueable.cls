public without sharing class TrafficOrderTransmitQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> budgetLineIds;
    private Id contractId;

    // Configure via Setup → Named Credentials → Traffic_System
    @TestVisible
    private static final String TRAFFIC_ENDPOINT = 'callout:Traffic_System/api/traffic/orders';

    public TrafficOrderTransmitQueueable(List<Id> budgetLineIds) {
        this.budgetLineIds = budgetLineIds;
    }

    public TrafficOrderTransmitQueueable(Id contractId) {
        this.contractId = contractId;
    }

    public void execute(QueueableContext ctx) {
        if (contractId != null) {
            executeForContract();
            return;
        }
        executeForBudgetLines();
    }

    private void executeForContract() {
        String correlationId = LogX.getGuid();
        currentCorrelationId = correlationId;

        Advertising_Contract__c contractUpdate = new Advertising_Contract__c(
            Id = contractId,
            Last_Traffic_Transmission__c = Datetime.now()
        );

        try {
            Map<String, Object> payload = new Map<String, Object>{
                'contractId' => contractId
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint(TRAFFIC_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(payload));
            req.setTimeout(10000);

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> body =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                contractUpdate.Traffic_Status__c = 'Transmitted';
                contractUpdate.Traffic_Order_ID__c = (String) body.get('orderId');
                contractUpdate.Traffic_Error_Message__c = null;
            } else {
                contractUpdate.Traffic_Status__c = 'Rejected';
                contractUpdate.Traffic_Error_Message__c =
                    'Traffic system returned HTTP ' + res.getStatusCode() + ': ' + res.getBody();
            }
        } catch (Exception ex) {
            LogX.logException(
                ex,
                'TrafficOrderTransmitQueueable.executeForContract failed (contractId=' + contractId + ')',
                correlationId,
                /* doEmit */ true
            );
            contractUpdate.Traffic_Status__c = 'Rejected';
            contractUpdate.Traffic_Error_Message__c = 'Callout failed: ' + ex.getMessage();
        }

        update contractUpdate;
    }

    private void executeForBudgetLines() {
        String correlationId = LogX.getGuid();
        currentCorrelationId = correlationId;

        try {
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

            Set<Id> oppIds = new Set<Id>();
            for (Budget_Line__c line : lines) {
                if (line.Opportunity__c != null) {
                    oppIds.add(line.Opportunity__c);
                }
            }

            Map<Id, Advertising_Contract__c> contractByOpp = queryContractsByOpp(oppIds);

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
        } catch (Exception ex) {
            LogX.logException(
                ex,
                'TrafficOrderTransmitQueueable.executeForBudgetLines failed (budgetLineIds=' +
                    (budgetLineIds == null ? 0 : budgetLineIds.size()) + ')',
                correlationId,
                /* doEmit */ true
            );
            throw ex;
        }
    }

    /**
     * Static slot for the current run's correlationId so callout() can attach
     * its per-row LogX entries without us threading the id through every
     * method signature. Set at the top of execute(); reset implicitly when
     * the next Queueable instance runs (statics reset between transactions).
     */
    @TestVisible
    private static String currentCorrelationId;

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
            // Log the per-callout failure to Log__c via LogX (correlationId
            // threaded from execute()'s static slot). The errorMessage stamp
            // on the Budget_Line__c row gives in-UI visibility; the Log__c
            // entry preserves the full exception detail + stack trace.
            LogX.logException(
                e,
                'TrafficOrderTransmitQueueable.callout failed (budgetLineId=' + line.Id + ')',
                currentCorrelationId,
                /* doEmit */ true
            );
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
