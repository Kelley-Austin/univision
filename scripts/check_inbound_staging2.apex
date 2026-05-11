Map<String, Schema.SObjectField> fields = Schema.SObjectType.Inbound_Staging__c.fields.getMap();
List<String> all = new List<String>(fields.keySet());
all.sort();
for (String f : all) {
    Schema.DescribeFieldResult d = fields.get(f).getDescribe();
    System.debug('  IS: ' + f + ' | ' + d.getType() + ' | externalId=' + d.isExternalId());
}
System.debug('TOTAL: ' + all.size());

// Source_System__c ref target
Schema.DescribeFieldResult ss = fields.get('source_system__c').getDescribe();
System.debug('Source_System__c ref: ' + ss.getReferenceTo());
