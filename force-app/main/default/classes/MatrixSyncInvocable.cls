public with sharing class MatrixSyncInvocable {

    public class TriggerRequest {
        @InvocableVariable(label='Unused — leave blank')
        public String unused;
    }

    @InvocableMethod(
        label='Trigger Manual Matrix Inventory Sync'
        description='Enqueues MatrixInventorySyncQueueable to run immediately. Use in the Admin Sync Screen Flow.'
    )
    public static List<String> triggerSync(List<TriggerRequest> requests) {
        System.enqueueJob(new MatrixInventorySyncQueueable(true));
        return new List<String>{ 'Sync queued successfully.' };
    }
}
