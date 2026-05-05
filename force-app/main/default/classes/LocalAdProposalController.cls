public with sharing class LocalAdProposalController {

    public Opportunity opp                  { get; private set; }
    public Account advertiser               { get; private set; }
    public List<Budget_Line__c> budgetLines { get; private set; }
    public Decimal totalPlanned             { get; private set; }
    public Boolean hasError                 { get; private set; }
    public String  errorMessage             { get; private set; }

    public LocalAdProposalController() {
        hasError = false;
        String oppId = ApexPages.currentPage().getParameters().get('id');

        if (String.isBlank(oppId)) {
            hasError     = true;
            errorMessage = 'No Opportunity ID provided. Please open this page from a Local Ad Sales opportunity record.';
            return;
        }

        try {
            opp = [
                SELECT Id, Name, AccountId, Market__c,
                       Start_Date__c, End_Date__c,
                       Primary_Demo__c, Secondary_Demo__c,
                       Proposal_Notes__c, Total_Budget__c,
                       Total_Planned_Amount__c, StageName, CreatedDate
                FROM Opportunity
                WHERE Id = :oppId
                LIMIT 1
            ];

            advertiser = [
                SELECT Id, Name, Phone,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode
                FROM Account
                WHERE Id = :opp.AccountId
                LIMIT 1
            ];

            budgetLines = [
                SELECT Id, Name,
                       Channel__r.Name, Channel__r.Channel_Type__c,
                       Vehicle__r.Name, Vehicle__r.Day_Part__c,
                       Vehicle__r.Rate_Card__c, Vehicle__r.Program__c,
                       Month__c, Fiscal_Year__c, Planned_Amount__c, Notes__c
                FROM Budget_Line__c
                WHERE Opportunity__c = :oppId
                ORDER BY Month__c, Channel__r.Name
            ];

            totalPlanned = 0;
            for (Budget_Line__c bl : budgetLines) {
                if (bl.Planned_Amount__c != null) {
                    totalPlanned += bl.Planned_Amount__c;
                }
            }

        } catch (Exception e) {
            hasError     = true;
            errorMessage = e.getMessage();
        }
    }
}
