/**
 * Invocable action behind the "Run Reconciliation" quick action on
 * Opportunity. Refreshes the Actual Revenue rollups for the
 * opportunity's Account so that pacing/variance calculations reflect the
 * latest matched actuals.
 *
 * Implementation: queries Actual_Revenue__c records for the opportunity's
 * Account (scoped to the opportunity's FiscalYear when set) and enqueues
 * ProjectionRollupQueueable to recompute Projection__c.Actual_Amount__c.
 *
 * Note: this action operates on already-matched Actual_Revenue__c records.
 * To match new inbound staging rows, run the source-system reconciliation
 * batch from Sales Operations Console (ReconciliationController.runBatch).
 */
public with sharing class RunReconciliationAction {

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
        description='Refreshes Actual Revenue rollups for the opportunity\'s Account. Updates Projection.Actual_Amount based on the latest matched actuals.'
        category='Advertising'
    )
    public static List<ReconciliationResult> run(List<ReconciliationRequest> requests) {
        List<ReconciliationResult> results = new List<ReconciliationResult>();

        // Bulk-load the opps in one query
        Set<Id> oppIds = new Set<Id>();
        for (ReconciliationRequest r : requests) {
            if (r.opportunityId != null) oppIds.add(r.opportunityId);
        }
        Map<Id, Opportunity> oppsById = new Map<Id, Opportunity>(
            [SELECT Id, AccountId, FiscalYear FROM Opportunity WHERE Id IN :oppIds]
        );

        for (ReconciliationRequest req : requests) {
            ReconciliationResult res = new ReconciliationResult();
            try {
                Opportunity opp = oppsById.get(req.opportunityId);
                if (opp == null) {
                    throw new IllegalArgumentException('Opportunity not found: ' + req.opportunityId);
                }
                if (opp.AccountId == null) {
                    res.success = false;
                    res.message = 'Cannot reconcile: this opportunity has no Account.';
                    results.add(res);
                    continue;
                }

                List<Actual_Revenue__c> actuals = (opp.FiscalYear != null)
                    ? [SELECT Id FROM Actual_Revenue__c
                       WHERE Account__c = :opp.AccountId AND Period_Year__c = :opp.FiscalYear]
                    : [SELECT Id FROM Actual_Revenue__c
                       WHERE Account__c = :opp.AccountId];

                if (actuals.isEmpty()) {
                    res.success = true;
                    res.message = 'No matched Actual Revenue records found for this Account'
                                + (opp.FiscalYear != null
                                    ? ' in fiscal year ' + opp.FiscalYear + '.'
                                    : '.')
                                + ' Nothing to roll up.';
                    results.add(res);
                    continue;
                }

                Set<Id> actualIds = new Set<Id>();
                for (Actual_Revenue__c a : actuals) actualIds.add(a.Id);

                Id jobId = System.enqueueJob(new ProjectionRollupQueueable(actualIds));

                res.success = true;
                res.message = 'Reconciliation queued for ' + actualIds.size()
                            + ' Actual Revenue record(s) (Job ID: ' + jobId
                            + '). Projections will refresh in a few minutes.';
            } catch (Exception e) {
                res.success = false;
                res.message = 'Could not start reconciliation: ' + e.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}
