public with sharing class TrafficOrderSubmitAction {

    public class Request {
        @InvocableVariable(required=true label='Budget Line Id')
        public Id budgetLineId;

        @InvocableVariable(required=true label='Copy Code')
        public String copyCode;

        @InvocableVariable(label='Copy Rotation')
        public String copyRotation;

        @InvocableVariable(label='Spot Length')
        public String spotLength;

        @InvocableVariable(label='Weekly Spots')
        public Integer weeklySpots;

        @InvocableVariable(label='Spot Rate')
        public Decimal spotRate;

        @InvocableVariable(label='Spot Instructions')
        public String spotInstructions;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Job Id')
        public String jobId;
    }

    @InvocableMethod(
        label='Submit Traffic Copy Entry'
        description='Saves spot-level copy details on the Budget Line, sets the parent contract Traffic_Status__c to Pending, and enqueues the traffic order for transmission.'
        category='Budget Line'
    )
    public static List<Result> submit(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(submitOne(req));
        }
        return results;
    }

    private static Result submitOne(Request req) {
        Result r = new Result();
        r.success = false;

        Budget_Line__c line;
        try {
            line = [
                SELECT Id, Name, Opportunity__c
                FROM Budget_Line__c
                WHERE Id = :req.budgetLineId
                LIMIT 1
            ];
        } catch (QueryException e) {
            r.errorMessage = 'Budget Line not found.';
            return r;
        }

        line.Copy_Code__c = req.copyCode;
        line.Copy_Rotation__c = req.copyRotation;
        line.Spot_Length__c = req.spotLength;
        line.Weekly_Spots__c = req.weeklySpots;
        line.Spot_Rate__c = req.spotRate;
        line.Spot_Instructions__c = req.spotInstructions;
        line.Traffic_Status__c = 'Pending';

        try {
            update line;
        } catch (DmlException e) {
            r.errorMessage = 'Failed to save Budget Line: ' + e.getDmlMessage(0);
            return r;
        }

        if (line.Opportunity__c != null) {
            List<Advertising_Contract__c> contracts = [
                SELECT Id, Traffic_Status__c
                FROM Advertising_Contract__c
                WHERE Opportunity__c = :line.Opportunity__c
                AND Contract_Status__c NOT IN ('Cancelled', 'Completed')
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!contracts.isEmpty()) {
                contracts[0].Traffic_Status__c = 'Pending';
                update contracts[0];
            }
        }

        Id jobId = System.enqueueJob(
            new TrafficOrderTransmitQueueable(new List<Id>{ req.budgetLineId })
        );

        r.success = true;
        r.jobId = String.valueOf(jobId);
        return r;
    }
}
