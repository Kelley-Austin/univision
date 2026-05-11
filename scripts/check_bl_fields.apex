// Check what fields are actually visible on Budget_Line__c in Apex schema
Map<String, Schema.SObjectField> fields = Schema.SObjectType.Budget_Line__c.fields.getMap();
List<String> customFields = new List<String>();
for (String f : fields.keySet()) {
    if (f.endsWith('__c') || f.endsWith('__r')) customFields.add(f);
}
customFields.sort();
System.debug('Budget_Line__c custom fields (' + customFields.size() + '): ' + JSON.serialize(customFields));
