Map<String, Schema.SObjectField> fields = Schema.SObjectType.Inbound_Staging__c.fields.getMap();
List<String> all = new List<String>(fields.keySet());
all.sort();
for (String f : all) {
    Schema.DescribeFieldResult d = fields.get(f).getDescribe();
    System.debug('  IS FIELD: ' + f + ' | ' + d.getType() + ' | nillable=' + d.isNillable() + ' | externalId=' + d.isExternalId());
}
System.debug('TOTAL: ' + all.size());

// Check Status__c picklist if it exists
try {
    DescribeFieldResult sr = Inbound_Staging__c.Status__c.getDescribe();
    List<String> vals = new List<String>();
    for(Schema.PicklistEntry e : sr.getPicklistValues()) vals.add(e.getValue());
    System.debug('STATUS PICKLIST: ' + JSON.serialize(vals));
} catch (Exception e) {
    System.debug('No Status__c: ' + e.getMessage());
}

// Source_System__c ref target
try {
    DescribeFieldResult ss = Inbound_Staging__c.Source_System__c.getDescribe();
    System.debug('Source_System__c ref target: ' + ss.getReferenceTo());
} catch (Exception e) {
    System.debug('Source_System__c error: ' + e.getMessage());
}
