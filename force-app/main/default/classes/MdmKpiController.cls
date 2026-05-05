public with sharing class MdmKpiController {

    @AuraEnabled(cacheable=true)
    public static KpiData getKpiData() {
        KpiData kpi = new KpiData();

        // Account counts grouped by record type developer name
        for (AggregateResult ar : [
            SELECT RecordType.DeveloperName rtype, COUNT(Id) cnt
            FROM Account
            WHERE RecordTypeId != null
            GROUP BY RecordType.DeveloperName
        ]) {
            String rtype = (String) ar.get('rtype');
            Integer cnt = (Integer) ar.get('cnt');
            if (rtype == 'HoldCo')       kpi.holdCoCount = cnt;
            else if (rtype == 'Agency')  kpi.agencyCount = cnt;
            else if (rtype == 'Advertiser') kpi.advertiserCount = cnt;
        }

        // Agencies with no parent + Advertisers with no parent
        kpi.orphanCount = [
            SELECT COUNT() FROM Account
            WHERE RecordType.DeveloperName IN ('Agency', 'Advertiser')
            AND ParentId = null
        ];

        // Active categories
        kpi.activeCategoryCount = [
            SELECT COUNT() FROM Category__c WHERE Is_Active__c = true
        ];

        // Accounts (with a Matrix record type) that have no Account_Category__c junction
        kpi.untaggedAccountCount = [
            SELECT COUNT() FROM Account
            WHERE RecordType.DeveloperName IN ('HoldCo', 'Agency', 'Advertiser')
            AND Id NOT IN (SELECT Account__c FROM Account_Category__c)
        ];

        return kpi;
    }

    public class KpiData {
        @AuraEnabled public Integer holdCoCount = 0;
        @AuraEnabled public Integer agencyCount = 0;
        @AuraEnabled public Integer advertiserCount = 0;
        @AuraEnabled public Integer orphanCount = 0;
        @AuraEnabled public Integer activeCategoryCount = 0;
        @AuraEnabled public Integer untaggedAccountCount = 0;
    }
}
