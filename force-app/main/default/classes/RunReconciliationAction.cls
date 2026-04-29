/**
 * Invocable action that kicks off ReconciliationBatch for an Advertising Opportunity.
 *
 * Call from a Flow's Action element on the Advertising Opportunity record page.
 * Returns a success flag and message so the flow can branch to a success or error screen.
 */
public class RunReconciliationAction {

    public class ReconciliationRequest {
        @InvocableVariable(label='Opportunity ID' description='ID of the Advertising Opportunity to reconcile.' required=true)
        public Id opportunityId;
    }

    public class ReconciliationResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='Run Reconciliation'
        description='Queues the ReconciliationBatch for an Advertising Opportunity. Matches Budget Lines against Counterpoint actuals and updates Reconciliation Lines.'
        category='Advertising'
    )
    public static List<ReconciliationResult> run(List<ReconciliationRequest> requests) {
        List<ReconciliationResult> results = new List<ReconciliationResult>();
        for (ReconciliationRequest req : requests) {
            ReconciliationResult res = new ReconciliationResult();
            try {
                Id jobId = Database.executeBatch(
                    new ReconciliationBatch(req.opportunityId), 200
                );
                res.success = true;
                res.message = 'Reconciliation queued (Job ID: ' + jobId
                            + '). Check Reconciliation Lines in a few minutes.';
            } catch (Exception e) {
                res.success = false;
                res.message = 'Could not start reconciliation: ' + e.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}
