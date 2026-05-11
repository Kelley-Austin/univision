DescribeFieldResult ch = Channel__c.Status__c.getDescribe();
List<String> chVals = new List<String>();
for(Schema.PicklistEntry e : ch.getPicklistValues()) chVals.add(e.getValue());
System.debug('CHANNEL STATUS: ' + JSON.serialize(chVals));
