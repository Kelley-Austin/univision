Map<String, Schema.SObjectField> fields = Schema.SObjectType.Source_System__c.fields.getMap();
List<String> all = new List<String>(fields.keySet());
all.sort();
for (String f : all) {
    System.debug('  SS: ' + f);
}
System.debug('TOTAL SS: ' + all.size());

Map<String, Schema.SObjectField> lbFields = Schema.SObjectType.Load_Batch__c.fields.getMap();
List<String> lbAll = new List<String>(lbFields.keySet());
lbAll.sort();
for (String f : lbAll) {
    System.debug('  LB: ' + f);
}
System.debug('TOTAL LB: ' + lbAll.size());

Map<String, Schema.SObjectField> psFields = Schema.SObjectType.Pacing_Snapshot__c.fields.getMap();
List<String> psAll = new List<String>(psFields.keySet());
psAll.sort();
for (String f : psAll) {
    System.debug('  PS: ' + f);
}
System.debug('TOTAL PS: ' + psAll.size());
