public with sharing class ProjectionTriggerHandler {

    public static void handle(List<Projection__c> records) {
        for (Projection__c proj : records) {
            proj.Composite_Key__c = buildCompositeKey(proj);
        }
    }

    public static String buildCompositeKey(Projection__c proj) {
        String accountPart  = proj.Account__c  != null ? String.valueOf(proj.Account__c)   : '';
        String categoryPart = proj.Category__c != null ? String.valueOf(proj.Category__c)  : '';
        String typePart     = proj.Revenue_Type__c != null ? proj.Revenue_Type__c           : '';
        String yearPart     = proj.Period_Year__c  != null ? String.valueOf(proj.Period_Year__c.intValue())  : '';
        String monthPart    = proj.Period_Month__c != null ? String.valueOf(proj.Period_Month__c.intValue()) : '';
        return accountPart + '|' + categoryPart + '|' + typePart + '|' + yearPart + '|' + monthPart;
    }
}
