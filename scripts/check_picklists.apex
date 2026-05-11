DescribeFieldResult sfn = Opportunity.StageName.getDescribe();
List<String> stageVals = new List<String>();
for(Schema.PicklistEntry e : sfn.getPicklistValues()) stageVals.add(e.getValue());
System.debug('OPP STAGES: ' + JSON.serialize(stageVals));

DescribeFieldResult csr = Advertising_Contract__c.Contract_Status__c.getDescribe();
List<String> csVals = new List<String>();
for(Schema.PicklistEntry e : csr.getPicklistValues()) csVals.add(e.getValue());
System.debug('CONTRACT STATUS: ' + JSON.serialize(csVals));

DescribeFieldResult bls = Budget_Line__c.Status__c.getDescribe();
List<String> blVals = new List<String>();
for(Schema.PicklistEntry e : bls.getPicklistValues()) blVals.add(e.getValue());
System.debug('BL STATUS: ' + JSON.serialize(blVals));

DescribeFieldResult ch = Budget_Line__c.Channel__c.getDescribe();
System.debug('BL CHANNEL REF TARGET: ' + ch.getReferenceTo());
