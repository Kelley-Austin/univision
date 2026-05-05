public with sharing class MatrixPromoteToContractAction {

    public class Request {
        @InvocableVariable(label='Advertising Opportunity ID' required=true)
        public Id opportunityId;

        @InvocableVariable(label='Ad Space IDs (comma-separated)')
        public String adSpaceIdsCsv;
    }

    public class Result {
        @InvocableVariable(label='Media Plan ID')
        public String mediaPlanId;

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Register Matrix Media Plan'
        description='Calls the Matrix API to create a media plan for the given Advertising Opportunity and stores the returned Media Plan ID on the record.'
    )
    public static List<Result> registerMediaPlan(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result res = new Result();
            try {
                List<String> adSpaceIds = new List<String>();
                if (String.isNotBlank(req.adSpaceIdsCsv)) {
                    for (String s : req.adSpaceIdsCsv.split(',')) {
                        String trimmed = s.trim();
                        if (String.isNotBlank(trimmed)) {
                            adSpaceIds.add(trimmed);
                        }
                    }
                }

                String planId = MatrixInventoryApiService.createMediaPlan(
                    String.valueOf(req.opportunityId),
                    adSpaceIds
                );

                update new Opportunity(
                    Id = req.opportunityId,
                    Media_Cloud_Media_Plan_ID__c = planId
                );

                res.mediaPlanId = planId;
                res.success = true;

            } catch (Exception e) {
                res.success = false;
                res.errorMessage = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}
