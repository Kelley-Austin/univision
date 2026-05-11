// Get ALL fields including namespaced ones
Map<String, Schema.SObjectField> fields = Schema.SObjectType.Budget_Line__c.fields.getMap();
List<String> all = new List<String>(fields.keySet());
all.sort();
for (String f : all) System.debug('  BL FIELD: ' + f);
System.debug('TOTAL: ' + all.size());
