public with sharing class MappingRuleService {

    @AuraEnabled(cacheable=true)
    public static List<Mapping_Rule__c> getRules(Id sourceSystemId) {
        return [
            SELECT Id, Name, Rule_Type__c, Field_Name__c, Raw_Value__c, Mapped_Value__c, Is_Active__c, Notes__c
            FROM Mapping_Rule__c
            WHERE Source_System__c = :sourceSystemId
            ORDER BY Rule_Type__c, Name
        ];
    }

    @AuraEnabled
    public static void saveRule(Mapping_Rule__c rule) {
        if (rule == null) throw new AuraHandledException('Rule is required.');
        upsert rule;
    }

    @AuraEnabled
    public static void activateRule(Id ruleId, Boolean isActive) {
        if (ruleId == null) throw new AuraHandledException('Rule ID is required.');
        update new Mapping_Rule__c(Id = ruleId, Is_Active__c = isActive);
    }

    @AuraEnabled
    public static void deleteRule(Id ruleId) {
        if (ruleId == null) throw new AuraHandledException('Rule ID is required.');
        delete new Mapping_Rule__c(Id = ruleId);
    }

    @AuraEnabled
    public static DryRunResult dryRun(Id sourceSystemId) {
        if (sourceSystemId == null) throw new AuraHandledException('Source System ID is required.');
        List<Mapping_Rule__c> activeRules = [
            SELECT Rule_Type__c, Field_Name__c, Raw_Value__c, Mapped_Value__c, Name
            FROM Mapping_Rule__c
            WHERE Source_System__c = :sourceSystemId AND Is_Active__c = true
        ];

        List<Inbound_Staging__c> pending = [
            SELECT Id, Raw_Advertiser_Name__c, Raw_Agency_Name__c, Raw_Salesperson_Code__c,
                   Revenue_Type__c, Outlet_Code__c, Status__c, Excluding_Rule__c
            FROM Inbound_Staging__c
            WHERE Source_System__c = :sourceSystemId AND Status__c = 'Pending'
            LIMIT 1000
        ];

        Integer wouldExclude = 0;
        Integer wouldRemap = 0;
        for (Inbound_Staging__c rec : pending) {
            for (Mapping_Rule__c rule : activeRules) {
                String val = getVal(rec, rule.Field_Name__c);
                if (val != null && val.equalsIgnoreCase(rule.Raw_Value__c)) {
                    if (rule.Rule_Type__c == 'Exclude') { wouldExclude++; break; }
                    else if (rule.Rule_Type__c == 'Map') { wouldRemap++; }
                }
            }
        }
        return new DryRunResult(pending.size(), wouldExclude, wouldRemap);
    }

    private static String getVal(Inbound_Staging__c rec, String field) {
        if (field == 'Raw_Advertiser_Name__c') return rec.Raw_Advertiser_Name__c;
        if (field == 'Raw_Agency_Name__c') return rec.Raw_Agency_Name__c;
        if (field == 'Raw_Salesperson_Code__c') return rec.Raw_Salesperson_Code__c;
        if (field == 'Revenue_Type__c') return rec.Revenue_Type__c;
        if (field == 'Outlet_Code__c') return rec.Outlet_Code__c;
        return null;
    }

    public class DryRunResult {
        @AuraEnabled public Integer pendingRows;
        @AuraEnabled public Integer wouldExclude;
        @AuraEnabled public Integer wouldRemap;
        public DryRunResult(Integer p, Integer e, Integer r) {
            pendingRows = p; wouldExclude = e; wouldRemap = r;
        }
    }
}
