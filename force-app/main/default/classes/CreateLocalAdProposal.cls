public with sharing class CreateLocalAdProposal {

    public class ProposalRequest {
        @InvocableVariable(required=true label='Account ID')
        public Id accountId;

        @InvocableVariable(label='Market')
        public String market;

        @InvocableVariable(required=true label='Flight Start Date')
        public Date startDate;

        @InvocableVariable(required=true label='Flight End Date')
        public Date endDate;

        @InvocableVariable(label='Primary Demo Target')
        public String primaryDemo;

        @InvocableVariable(label='Secondary Demo Target')
        public String secondaryDemo;

        @InvocableVariable(label='Proposal Notes')
        public String proposalNotes;

        @InvocableVariable(label='Total Budget')
        public Decimal totalBudget;

        @InvocableVariable(label='Vehicle ID')
        public Id vehicleId;

        @InvocableVariable(label='Budget Lines JSON')
        public String budgetLinesJson;
    }

    public class ProposalResult {
        @InvocableVariable(label='Opportunity ID')
        public Id opportunityId;

        @InvocableVariable(label='Opportunity Name')
        public String opportunityName;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Success')
        public Boolean success;
    }

    @InvocableMethod(
        label='Create Local Ad Proposal'
        description='Creates an Advertising Opportunity (Local Ad Sales record type) with linked Budget Lines in a single transaction. Rolls back on any failure.'
    )
    public static List<ProposalResult> createProposal(List<ProposalRequest> requests) {
        List<ProposalResult> results = new List<ProposalResult>();

        for (ProposalRequest req : requests) {
            Savepoint sp = Database.setSavepoint();
            ProposalResult result = new ProposalResult();

            try {
                Id rtId = Schema.SObjectType.Advertising_Opportunity__c
                    .getRecordTypeInfosByDeveloperName()
                    .get('Local_Ad_Sales')
                    .getRecordTypeId();

                Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
                    RecordTypeId   = rtId,
                    Account__c     = req.accountId,
                    Market__c      = req.market,
                    Start_Date__c  = req.startDate,
                    End_Date__c    = req.endDate,
                    Primary_Demo__c   = req.primaryDemo,
                    Secondary_Demo__c = req.secondaryDemo,
                    Proposal_Notes__c = req.proposalNotes,
                    Total_Budget__c   = req.totalBudget,
                    Status__c         = 'Draft'
                );
                insert opp;

                Decimal totalPlanned = 0;
                List<Budget_Line__c> budgetLines = new List<Budget_Line__c>();

                if (String.isNotBlank(req.budgetLinesJson)) {
                    List<Object> lineObjects = (List<Object>) JSON.deserializeUntyped(req.budgetLinesJson);

                    for (Object obj : lineObjects) {
                        Map<String, Object> line = (Map<String, Object>) obj;

                        Decimal amount = 0;
                        if (line.get('plannedAmount') != null) {
                            amount = Decimal.valueOf(String.valueOf(line.get('plannedAmount')));
                        }
                        totalPlanned += amount;

                        Budget_Line__c bl = new Budget_Line__c(
                            Advertising_Opportunity__c = opp.Id,
                            Account__c     = req.accountId,
                            Vehicle__c     = req.vehicleId,
                            Channel__c     = line.get('channelId') != null
                                                 ? (Id) line.get('channelId')
                                                 : null,
                            Month__c       = (String) line.get('month'),
                            Fiscal_Year__c = (String) line.get('fiscalYear'),
                            Planned_Amount__c = amount,
                            Notes__c       = (String) line.get('notes'),
                            Status__c      = 'Draft'
                        );
                        budgetLines.add(bl);
                    }
                }

                if (!budgetLines.isEmpty()) {
                    insert budgetLines;
                }

                opp.Total_Planned_Amount__c = totalPlanned;
                update opp;

                Advertising_Opportunity__c requeried = [
                    SELECT Id, Name
                    FROM Advertising_Opportunity__c
                    WHERE Id = :opp.Id
                ];

                result.opportunityId   = requeried.Id;
                result.opportunityName = requeried.Name;
                result.success         = true;

            } catch (Exception e) {
                Database.rollback(sp);
                result.success      = false;
                result.errorMessage = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<Channel__c> getActiveChannels() {
        return [
            SELECT Id, Name, Channel_Type__c, Market__c
            FROM Channel__c
            WHERE Status__c = 'Active'
            ORDER BY Name
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Vehicle__c> getActiveVehicles() {
        return [
            SELECT Id, Name, Day_Part__c, Rate_Card__c, Program__c, Vehicle_Code__c, Market__c
            FROM Vehicle__c
            WHERE Status__c = 'Active'
            ORDER BY Name
        ];
    }
}
