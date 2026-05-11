// Simulate the same sequence as seed script: insert accounts first, then bulk opps
List<Account> advertisers = new List<Account>{
    new Account(Name='TEST Jeep Retail Corp.',              RecordTypeId='012NS00000CTRNhYAP', Industry='Automotive'),
    new Account(Name='TEST Ram Truck Retail Corp',          RecordTypeId='012NS00000CTRNhYAP', Industry='Automotive'),
    new Account(Name='TEST Jack in the Box Inc.',           RecordTypeId='012NS00000CTRNhYAP', Industry='Food & Beverage'),
    new Account(Name='TEST Ultimate Fighting Championship', RecordTypeId='012NS00000CTRNhYAP', Industry='Entertainment'),
    new Account(Name='TEST 4U Realty Plus, LLC',            RecordTypeId='012NS00000CTRNhYAP', Industry='Real Estate'),
    new Account(Name='TEST AdventHealth',                   RecordTypeId='012NS00000CTRNhYAP', Industry='Healthcare'),
    new Account(Name='TEST AdsWizz, Inc.',                  RecordTypeId='012NS00000CTRNhYAP', Industry='Technology'),
    new Account(Name='TEST Dept. of Homeland Security',     RecordTypeId='012NS00000CTRNhYAP', Industry='Government')
};
insert advertisers;
Map<String,Id> advIds = new Map<String,Id>();
for (Account a : advertisers) advIds.put(a.Name.removeStart('TEST '), a.Id);

// Insert opps one at a time to find which fails
List<Opportunity> allOpps = new List<Opportunity>{
    new Opportunity(Name='TEST Jeep EUVF TV Q3',     AccountId=advIds.get('Jeep Retail Corp.'),              StageName='Stage 3 - Pipeline/Deal',   CloseDate=Date.newInstance(2026,9,30),  Start_Date__c=Date.newInstance(2026,7,1),  End_Date__c=Date.newInstance(2026,9,30),  Amount=55000,  Market__c='Detroit',    Description='CoxReps [TV-Linear]'),
    new Opportunity(Name='TEST Jeep Digital Q4',     AccountId=advIds.get('Jeep Retail Corp.'),              StageName='Stage 4 - Negotiation',     CloseDate=Date.newInstance(2026,11,15), Start_Date__c=Date.newInstance(2026,10,1), End_Date__c=Date.newInstance(2026,12,31), Amount=28500,  Market__c='Detroit',    Description='CoxReps [Digital]'),
    new Opportunity(Name='TEST Ram EUVF TV Q3',      AccountId=advIds.get('Ram Truck Retail Corp'),          StageName='Stage 5 - Contract Pending', CloseDate=Date.newInstance(2026,8,31),  Start_Date__c=Date.newInstance(2026,7,1),  End_Date__c=Date.newInstance(2026,9,30),  Amount=41750,  Market__c='Detroit',    Description='CoxReps [TV-Linear]'),
    new Opportunity(Name='TEST JitB KBNT Radio Q3',  AccountId=advIds.get('Jack in the Box Inc.'),           StageName='Stage 2 - Discovery/CNA',   CloseDate=Date.newInstance(2026,9,30),  Start_Date__c=Date.newInstance(2026,7,1),  End_Date__c=Date.newInstance(2026,9,30),  Amount=12000,  Market__c='San Diego',  Description='CoxReps [Radio-Linear]'),
    new Opportunity(Name='TEST UFC KBNT Digital',    AccountId=advIds.get('Ultimate Fighting Championship'), StageName='Stage 3 - Pipeline/Deal',   CloseDate=Date.newInstance(2026,10,31), Start_Date__c=Date.newInstance(2026,9,1),  End_Date__c=Date.newInstance(2026,12,31), Amount=25000,  Market__c='Minneapolis',Description='CoxReps [Digital]'),
    new Opportunity(Name='TEST AdventHealth TV Q1',  AccountId=advIds.get('AdventHealth'),                   StageName='Closed Won',                CloseDate=Date.newInstance(2026,1,31),  Start_Date__c=Date.newInstance(2026,1,1),  End_Date__c=Date.newInstance(2026,3,31),  Amount=16182,  Market__c='Orlando',    Description='Strata [TV-Linear]'),
    new Opportunity(Name='TEST AdventHealth TV Q2',  AccountId=advIds.get('AdventHealth'),                   StageName='Stage 4 - Negotiation',     CloseDate=Date.newInstance(2026,5,31),  Start_Date__c=Date.newInstance(2026,4,1),  End_Date__c=Date.newInstance(2026,9,30),  Amount=35892,  Market__c='Orlando',    Description='Strata [TV-Linear]'),
    new Opportunity(Name='TEST AdsWizz Digital',     AccountId=advIds.get('AdsWizz, Inc.'),                  StageName='Stage 1 - Lead',            CloseDate=Date.newInstance(2026,6,30),  Start_Date__c=Date.newInstance(2026,1,1),  End_Date__c=Date.newInstance(2026,6,30),  Amount=291751, Market__c='Corporate',  Description='Strata [Digital]'),
    new Opportunity(Name='TEST 4U Radio Phoenix',    AccountId=advIds.get('4U Realty Plus, LLC'),            StageName='Stage 3 - Pipeline/Deal',   CloseDate=Date.newInstance(2026,9,30),  Start_Date__c=Date.newInstance(2026,4,1),  End_Date__c=Date.newInstance(2026,12,31), Amount=38955,  Market__c='Phoenix',    Description='Strata [Radio-Digital]'),
    new Opportunity(Name='TEST DHS KBNT TV',         AccountId=advIds.get('Dept. of Homeland Security'),     StageName='Stage 5 - Contract Pending', CloseDate=Date.newInstance(2026,10,31), Start_Date__c=Date.newInstance(2026,9,1),  End_Date__c=Date.newInstance(2026,11,30), Amount=19550,  Market__c='San Diego',  Description='CoxReps [TV-Linear]'),
    new Opportunity(Name='TEST 4U TV Phoenix Q4',    AccountId=advIds.get('4U Realty Plus, LLC'),            StageName='Stage 2 - Discovery/CNA',   CloseDate=Date.newInstance(2026,10,31), Start_Date__c=Date.newInstance(2026,10,1), End_Date__c=Date.newInstance(2026,12,31), Amount=9885,   Market__c='Phoenix',    Description='Strata [TV-Linear]'),
    new Opportunity(Name='TEST AdventHealth Radio Q1',AccountId=advIds.get('AdventHealth'),                  StageName='Closed Won',                CloseDate=Date.newInstance(2026,1,15),  Start_Date__c=Date.newInstance(2026,1,1),  End_Date__c=Date.newInstance(2026,3,31),  Amount=14890,  Market__c='Orlando',    Description='Strata [Radio-Linear]')
};

List<Opportunity> toDelete = new List<Opportunity>();
for (Integer i = 0; i < allOpps.size(); i++) {
    try {
        insert allOpps[i];
        System.debug('OK [' + i + ']: ' + allOpps[i].Name);
        toDelete.add(allOpps[i]);
    } catch (DmlException e) {
        System.debug('FAIL [' + i + '] ' + allOpps[i].Name + ': ' + e.getDmlMessage(0));
    }
}
if (!toDelete.isEmpty()) delete toDelete;
delete advertisers;
System.debug('Done. Cleaned ' + toDelete.size() + ' opps and ' + advertisers.size() + ' accounts.');
