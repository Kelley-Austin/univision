public with sharing class IngestTriggerController {
    @AuraEnabled
    public static void enqueueIngest(Id contentVersionId, Id sourceSystemId) {
        System.enqueueJob(new IngestQueueable(contentVersionId, sourceSystemId));
    }
}
