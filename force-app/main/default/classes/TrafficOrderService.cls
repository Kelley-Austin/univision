/**
 * Invocable entry point called by the "Transmit Traffic Order on Contract Activation"
 * Record-Triggered Flow. Sets Traffic_Status__c = Pending, generates a one-time
 * callback authentication token, and enqueues TrafficOrderTransmitQueueable to
 * make the HTTP callout outside the triggering transaction.
 */
public with sharing class TrafficOrderService {

    public class TransmitRequest {
        @InvocableVariable(label='Contract ID' required=true)
        public Id contractId;
    }

    @InvocableMethod(
        label='Enqueue Traffic Order Transmission'
        description='Marks the contract as Pending and enqueues the outbound callout to the traffic system.'
        category='Traffic'
    )
    public static void enqueueTransmission(List<TransmitRequest> requests) {
        List<Advertising_Contract__c> toUpdate = new List<Advertising_Contract__c>();
        for (TransmitRequest req : requests) {
            toUpdate.add(new Advertising_Contract__c(
                Id = req.contractId,
                Traffic_Status__c = 'Pending',
                Traffic_Callback_Token__c = generateCallbackToken(),
                Last_Traffic_Transmission__c = Datetime.now()
            ));
        }
        update toUpdate;

        for (TransmitRequest req : requests) {
            System.enqueueJob(new TrafficOrderTransmitQueueable(req.contractId));
        }
    }

    @TestVisible
    private static String generateCallbackToken() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 32);
    }
}
