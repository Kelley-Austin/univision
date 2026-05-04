public with sharing class MappingRuleExecutor {
    private List<Mapping_Rule__c> excludeRules;
    private List<Mapping_Rule__c> mapRules;

    public MappingRuleExecutor(Id sourceSystemId) {
        List<Mapping_Rule__c> rules = [
            SELECT Rule_Type__c, Field_Name__c, Raw_Value__c, Mapped_Value__c, Name
            FROM Mapping_Rule__c
            WHERE Source_System__c = :sourceSystemId AND Is_Active__c = true
            ORDER BY Rule_Type__c, Name
        ];
        excludeRules = new List<Mapping_Rule__c>();
        mapRules = new List<Mapping_Rule__c>();
        for (Mapping_Rule__c r : rules) {
            if (r.Rule_Type__c == 'Exclude') excludeRules.add(r);
            else if (r.Rule_Type__c == 'Map') mapRules.add(r);
        }
    }

    public void apply(List<Inbound_Staging__c> records) {
        for (Inbound_Staging__c rec : records) {
            if (rec.Status__c == 'Excluded' || rec.Status__c == 'Error') continue;
            applyExclusions(rec);
            if (rec.Status__c != 'Excluded') applyMappings(rec);
        }
    }

    private void applyExclusions(Inbound_Staging__c rec) {
        for (Mapping_Rule__c rule : excludeRules) {
            String fieldVal = getFieldValue(rec, rule.Field_Name__c);
            if (fieldVal != null && fieldVal.equalsIgnoreCase(rule.Raw_Value__c)) {
                rec.Status__c = 'Excluded';
                rec.Excluding_Rule__c = rule.Name;
                return;
            }
        }
    }

    private void applyMappings(Inbound_Staging__c rec) {
        for (Mapping_Rule__c rule : mapRules) {
            String fieldVal = getFieldValue(rec, rule.Field_Name__c);
            if (fieldVal != null && fieldVal.equalsIgnoreCase(rule.Raw_Value__c)) {
                setFieldValue(rec, rule.Field_Name__c, rule.Mapped_Value__c);
            }
        }
    }

    // Only canonical staging text fields are mappable via rules
    private String getFieldValue(Inbound_Staging__c rec, String fieldName) {
        if (fieldName == 'Raw_Advertiser_Name__c') return rec.Raw_Advertiser_Name__c;
        if (fieldName == 'Raw_Agency_Name__c') return rec.Raw_Agency_Name__c;
        if (fieldName == 'Raw_Salesperson_Code__c') return rec.Raw_Salesperson_Code__c;
        if (fieldName == 'Revenue_Type__c') return rec.Revenue_Type__c;
        if (fieldName == 'Outlet_Code__c') return rec.Outlet_Code__c;
        return null;
    }

    private void setFieldValue(Inbound_Staging__c rec, String fieldName, String value) {
        if (fieldName == 'Raw_Advertiser_Name__c') rec.Raw_Advertiser_Name__c = value;
        else if (fieldName == 'Raw_Agency_Name__c') rec.Raw_Agency_Name__c = value;
        else if (fieldName == 'Raw_Salesperson_Code__c') rec.Raw_Salesperson_Code__c = value;
        else if (fieldName == 'Revenue_Type__c') rec.Revenue_Type__c = value;
        else if (fieldName == 'Outlet_Code__c') rec.Outlet_Code__c = value;
    }
}
