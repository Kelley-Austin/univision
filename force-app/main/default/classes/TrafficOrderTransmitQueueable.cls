/**
 * Queueable job that builds a structured traffic order payload from an Advertising Contract
 * and its related Budget Lines, then POSTs it to the traffic system via the Traffic_System
 * Named Credential. Updates Traffic_Status__c and Traffic_Order_ID__c based on the response.
 *
 * Transmission window: the job runs within seconds of enqueueing. The one-hour SLA
 * in the acceptance criteria is met as long as the Salesforce async queue is not backed up.
 */
public class TrafficOrderTransmitQueueable implements Queueable, Database.AllowsCallouts {

    private static final String ENDPOINT = 'callout:Traffic_System/orders';
    private static final Integer TIMEOUT_MS = 30000;

    private final Id contractId;

    public TrafficOrderTransmitQueueable(Id contractId) {
        this.contractId = contractId;
    }

    public void execute(QueueableContext ctx) {
        Advertising_Contract__c contract = queryContract();
        List<Budget_Line__c> spots = querySpots(contract.Advertising_Opportunity__c);

        Advertising_Contract__c result = new Advertising_Contract__c(Id = contractId);
        result.Last_Traffic_Transmission__c = Datetime.now();

        try {
            HttpResponse res = transmit(contract, spots);

            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                result.Traffic_Status__c = 'Transmitted';
                result.Traffic_Order_ID__c = (String) body.get('orderId');
                result.Traffic_Error_Message__c = null;
            } else {
                result.Traffic_Status__c = 'Rejected';
                result.Traffic_Error_Message__c = buildHttpError(res);
            }
        } catch (Exception e) {
            result.Traffic_Status__c = 'Rejected';
            result.Traffic_Error_Message__c = e.getMessage();
        }

        update result;
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private Advertising_Contract__c queryContract() {
        return [
            SELECT Id, Name, Advertising_Opportunity__c,
                   Account__c, Account__r.Name,
                   Agency_Account__c, Agency_Account__r.Name,
                   Start_Date__c, End_Date__c,
                   Total_Contract_Value__c, Market__c,
                   Cancellation_Policy__c, Make_Good_Policy__c, Make_Good_Credits__c,
                   Traffic_Callback_Token__c
            FROM Advertising_Contract__c
            WHERE Id = :contractId
            LIMIT 1
        ];
    }

    private List<Budget_Line__c> querySpots(Id opportunityId) {
        if (opportunityId == null) {
            return new List<Budget_Line__c>();
        }
        return [
            SELECT Id, Name,
                   Vehicle__c, Vehicle__r.Vehicle_Code__c, Vehicle__r.Name,
                   Vehicle__r.Day_Part__c, Vehicle__r.Program__c,
                   Date_Type__c, Calendar_Date__c, Broadcast_Date__c,
                   Copy_Code__c, Copy_Rotation__c, Spot_Length__c,
                   Weekly_Spots__c, Spot_Rate__c, Spot_Instructions__c
            FROM Budget_Line__c
            WHERE Advertising_Opportunity__c = :opportunityId
            ORDER BY Broadcast_Date__c NULLS LAST, Calendar_Date__c NULLS LAST
        ];
    }

    @TestVisible
    private HttpResponse transmit(Advertising_Contract__c contract, List<Budget_Line__c> spots) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(buildPayload(contract, spots)));

        return new Http().send(req);
    }

    private Map<String, Object> buildPayload(Advertising_Contract__c c, List<Budget_Line__c> spots) {
        List<Map<String, Object>> spotList = new List<Map<String, Object>>();
        for (Budget_Line__c line : spots) {
            spotList.add(new Map<String, Object>{
                'lineId'            => line.Name,
                'vehicleCode'       => line.Vehicle__r.Vehicle_Code__c,
                'vehicleName'       => line.Vehicle__r.Name,
                'dayPart'           => line.Vehicle__r.Day_Part__c,
                'program'           => line.Vehicle__r.Program__c,
                'dateType'          => line.Date_Type__c,
                'broadcastDate'     => line.Broadcast_Date__c != null
                                            ? String.valueOf(line.Broadcast_Date__c) : null,
                'calendarDate'      => line.Calendar_Date__c != null
                                            ? String.valueOf(line.Calendar_Date__c) : null,
                'copyCode'          => line.Copy_Code__c,
                'copyRotation'      => line.Copy_Rotation__c,
                'spotLength'        => line.Spot_Length__c,
                'weeklySpots'       => line.Weekly_Spots__c,
                'spotRate'          => line.Spot_Rate__c,
                'spotInstructions'  => line.Spot_Instructions__c
            });
        }

        return new Map<String, Object>{
            'orderId'               => c.Name,
            'advertiserId'          => c.Account__c,
            'advertiserName'        => c.Account__r.Name,
            'agencyId'              => c.Agency_Account__c,
            'agencyName'            => c.Agency_Account__r.Name,
            'market'                => c.Market__c,
            'flightStart'           => c.Start_Date__c != null
                                            ? String.valueOf(c.Start_Date__c) : null,
            'flightEnd'             => c.End_Date__c != null
                                            ? String.valueOf(c.End_Date__c) : null,
            'totalValue'            => c.Total_Contract_Value__c,
            'cancellationPolicy'    => c.Cancellation_Policy__c,
            'makeGoodPolicy'        => c.Make_Good_Policy__c,
            'makeGoodCredits'       => c.Make_Good_Credits__c,
            'callbackToken'         => c.Traffic_Callback_Token__c,
            'spots'                 => spotList
        };
    }

    private static String buildHttpError(HttpResponse res) {
        String body = res.getBody();
        if (body != null && body.length() > 1900) {
            body = body.substring(0, 1900) + '...';
        }
        return 'HTTP ' + res.getStatusCode() + ' ' + res.getStatus() + ': ' + body;
    }
}
