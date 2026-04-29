public with sharing class CreateOpportunityWithBudgetLines {

    public class OpportunityRequest {
        @InvocableVariable(required=true label='Account ID')
        public Id accountId;

        @InvocableVariable(label='Agency Account ID')
        public Id agencyAccountId;

        @InvocableVariable(label='Start Date')
        public Date startDate;

        @InvocableVariable(label='End Date')
        public Date endDate;

        @InvocableVariable(label='Market')
        public String market;

        @InvocableVariable(label='Fiscal Year')
        public String fiscalYear;

        @InvocableVariable(label='Total Budget')
        public Decimal totalBudget;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Budget Lines JSON')
        public String budgetLinesJson;
    }

    public class OpportunityResult {
        @InvocableVariable(label='Opportunity ID')
        public String opportunityId;

        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Create Opportunity With Budget Lines'
        description='Creates Advertising_Opportunity__c and Budget_Line__c records in one transaction; rolls back on any failure'
    )
    public static List<OpportunityResult> createOpportunityWithBudgetLines(List<OpportunityRequest> requests) {
        List<OpportunityResult> results = new List<OpportunityResult>();

        for (OpportunityRequest req : requests) {
            Savepoint sp = Database.setSavepoint();
            OpportunityResult result = new OpportunityResult();

            try {
                Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
                    Account__c        = req.accountId,
                    Agency_Account__c = req.agencyAccountId,
                    Start_Date__c     = req.startDate,
                    End_Date__c       = req.endDate,
                    Market__c         = req.market,
                    Fiscal_Year__c    = req.fiscalYear,
                    Total_Budget__c   = req.totalBudget,
                    Status__c         = String.isBlank(req.status) ? 'Draft' : req.status
                );
                insert opp;

                if (String.isNotBlank(req.budgetLinesJson)) {
                    List<Object> rawLines = (List<Object>) JSON.deserializeUntyped(req.budgetLinesJson);

                    if (!rawLines.isEmpty()) {
                        List<Budget_Line__c> lines = new List<Budget_Line__c>();
                        Decimal totalPlanned = 0;

                        for (Object raw : rawLines) {
                            Map<String, Object> lineMap = (Map<String, Object>) raw;
                            Decimal amt = lineMap.get('plannedAmount') != null
                                ? Decimal.valueOf(String.valueOf(lineMap.get('plannedAmount')))
                                : 0;
                            totalPlanned += amt;

                            lines.add(new Budget_Line__c(
                                Advertising_Opportunity__c = opp.Id,
                                Account__c                 = req.accountId,
                                Channel__c                 = (Id) lineMap.get('channelId'),
                                Month__c                   = (String) lineMap.get('month'),
                                Fiscal_Year__c             = (String) lineMap.get('fiscalYear'),
                                Planned_Amount__c          = amt,
                                Notes__c                   = (String) lineMap.get('notes'),
                                Status__c                  = 'Draft'
                            ));
                        }

                        insert lines;

                        opp.Total_Planned_Amount__c = totalPlanned;
                        update opp;
                    }
                }

                result.opportunityId = opp.Id;
                result.isSuccess = true;

            } catch (Exception e) {
                Database.rollback(sp);
                result.isSuccess = false;
                result.errorMessage = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<Channel__c> getActiveChannels() {
        return [
            SELECT Id, Name, Channel_Type__c, Market__c, Channel_Code__c
            FROM Channel__c
            WHERE Status__c = 'Active'
            ORDER BY Name
            LIMIT 200
        ];
    }
}
