Id rtAdvertiser = '012NS00000CTRNhYAP';
Id rtAgency     = '012NS00000CTRNiYAP';

// Step 1: Agencies
System.debug('=== STEP 1: AGENCIES ===');
List<Account> agencies = new List<Account>{
    new Account(Name='DBG Starcom Media Services',  RecordTypeId=rtAgency, Phone='312-220-3500'),
    new Account(Name='DBG Carat USA, Inc.',          RecordTypeId=rtAgency, Phone='212-591-9200'),
    new Account(Name='DBG Brown Parker & DeMarinis', RecordTypeId=rtAgency, Phone='407-843-6000'),
    new Account(Name='DBG Strategic Media Services', RecordTypeId=rtAgency, Phone='703-524-4000')
};
Database.SaveResult[] ar = Database.insert(agencies, false);
for (Integer i = 0; i < ar.size(); i++) {
    if (ar[i].isSuccess()) System.debug('  OK agency[' + i + ']: ' + agencies[i].Id);
    else System.debug('  FAIL agency[' + i + ']: ' + ar[i].getErrors()[0].getMessage());
}

// Step 2: Advertisers
System.debug('=== STEP 2: ADVERTISERS ===');
List<Account> advertisers = new List<Account>{
    new Account(Name='DBG Jeep Retail Corp.',              RecordTypeId=rtAdvertiser, Industry='Automotive'),
    new Account(Name='DBG Ram Truck Retail Corp',          RecordTypeId=rtAdvertiser, Industry='Automotive'),
    new Account(Name='DBG Jack in the Box Inc.',           RecordTypeId=rtAdvertiser, Industry='Food & Beverage'),
    new Account(Name='DBG Ultimate Fighting Championship', RecordTypeId=rtAdvertiser, Industry='Entertainment'),
    new Account(Name='DBG 4U Realty Plus, LLC',            RecordTypeId=rtAdvertiser, Industry='Real Estate'),
    new Account(Name='DBG AdventHealth',                   RecordTypeId=rtAdvertiser, Industry='Healthcare'),
    new Account(Name='DBG AdsWizz, Inc.',                  RecordTypeId=rtAdvertiser, Industry='Technology'),
    new Account(Name='DBG Dept. of Homeland Security',     RecordTypeId=rtAdvertiser, Industry='Government')
};
Database.SaveResult[] adr = Database.insert(advertisers, false);
Map<String,Id> advIds = new Map<String,Id>();
for (Integer i = 0; i < adr.size(); i++) {
    if (adr[i].isSuccess()) {
        advIds.put(advertisers[i].Name.removeStart('DBG '), advertisers[i].Id);
        System.debug('  OK advertiser[' + i + ']: ' + advertisers[i].Id);
    } else {
        System.debug('  FAIL advertiser[' + i + ']: ' + adr[i].getErrors()[0].getMessage());
    }
}

// Step 3: Opportunities - test one by one with partial save to isolate
System.debug('=== STEP 3: OPPS (with partial success) ===');
List<Opportunity> opps = new List<Opportunity>{
    new Opportunity(Name='DBG Jeep Retail Corp. — EUVF TV Q3 2026',            AccountId=advIds.get('Jeep Retail Corp.'),              StageName='Stage 3 - Pipeline/Deal',   CloseDate=Date.newInstance(2026,9,30),  Start_Date__c=Date.newInstance(2026,7,1),  End_Date__c=Date.newInstance(2026,9,30),  Amount=55000,  Market__c='Detroit',     Description='CoxReps — TeleRep Sun Broadcasting, EUVF. A25-54 Time Sale. [TV-Linear]'),
    new Opportunity(Name='DBG Jeep Retail Corp. — Digital Display Q4 2026',    AccountId=advIds.get('Jeep Retail Corp.'),              StageName='Stage 4 - Negotiation',     CloseDate=Date.newInstance(2026,11,15), Start_Date__c=Date.newInstance(2026,10,1), End_Date__c=Date.newInstance(2026,12,31), Amount=28500,  Market__c='Detroit',     Description='CoxReps — Digital extension of EUVF buy. [Digital]'),
    new Opportunity(Name='DBG Ram Truck Retail Corp — EUVF TV Q3 2026',        AccountId=advIds.get('Ram Truck Retail Corp'),          StageName='Stage 5 - Contract Pending', CloseDate=Date.newInstance(2026,8,31),  Start_Date__c=Date.newInstance(2026,7,1),  End_Date__c=Date.newInstance(2026,9,30),  Amount=41750,  Market__c='Detroit',     Description='CoxReps — TeleRep Sun Broadcasting, EUVF. A25-54 & RA35+. [TV-Linear]'),
    new Opportunity(Name='DBG Jack in the Box Inc. — KBNT Radio Q3 2026',      AccountId=advIds.get('Jack in the Box Inc.'),           StageName='Stage 2 - Discovery/CNA',   CloseDate=Date.newInstance(2026,9,30),  Start_Date__c=Date.newInstance(2026,7,1),  End_Date__c=Date.newInstance(2026,9,30),  Amount=12000,  Market__c='San Diego',   Description='CoxReps — Carat USA. QSR fastfood flight, A25-54. [Radio-Linear]'),
    new Opportunity(Name='DBG UFC — KBNT Digital 2026',                        AccountId=advIds.get('Ultimate Fighting Championship'), StageName='Stage 3 - Pipeline/Deal',   CloseDate=Date.newInstance(2026,10,31), Start_Date__c=Date.newInstance(2026,9,1),  End_Date__c=Date.newInstance(2026,12,31), Amount=25000,  Market__c='Minneapolis', Description='CoxReps — JSML Media LLC. RM21-49 demo. [Digital]'),
    new Opportunity(Name='DBG AdventHealth — Orlando DIG TV Q1 2026',          AccountId=advIds.get('AdventHealth'),                   StageName='Closed Won',                CloseDate=Date.newInstance(2026,1,31),  Start_Date__c=Date.newInstance(2026,1,1),  End_Date__c=Date.newInstance(2026,3,31),  Amount=16182,  Market__c='Orlando',     Description='Strata — Brown Parker & DeMarinis. AdventHealth healthcare Q1 flight. [TV-Linear]'),
    new Opportunity(Name='DBG AdventHealth — Orlando DIG TV Q2-Q3 2026',       AccountId=advIds.get('AdventHealth'),                   StageName='Stage 4 - Negotiation',     CloseDate=Date.newInstance(2026,5,31),  Start_Date__c=Date.newInstance(2026,4,1),  End_Date__c=Date.newInstance(2026,9,30),  Amount=35892,  Market__c='Orlando',     Description='Strata — Brown Parker & DeMarinis. AdventHealth renewal Q2–Q3. [TV-Linear]'),
    new Opportunity(Name='DBG AdsWizz, Inc. — Corporate TV Digital 2026',      AccountId=advIds.get('AdsWizz, Inc.'),                  StageName='Stage 1 - Lead',            CloseDate=Date.newInstance(2026,6,30),  Start_Date__c=Date.newInstance(2026,1,1),  End_Date__c=Date.newInstance(2026,6,30),  Amount=291751, Market__c='Corporate',   Description='Strata — NoAE Local. AdsWizz programmatic streaming. H1 2026. [Digital]'),
    new Opportunity(Name='DBG 4U Realty Plus — Phoenix Radio Digital 2026',    AccountId=advIds.get('4U Realty Plus, LLC'),            StageName='Stage 3 - Pipeline/Deal',   CloseDate=Date.newInstance(2026,9,30),  Start_Date__c=Date.newInstance(2026,4,1),  End_Date__c=Date.newInstance(2026,12,31), Amount=38955,  Market__c='Phoenix',     Description='Strata — David Acosta. Local Phoenix DIG, Real Estate Agents category. [Radio-Digital]'),
    new Opportunity(Name='DBG Dept. of Homeland Security — KBNT TV Political', AccountId=advIds.get('Dept. of Homeland Security'),     StageName='Stage 5 - Contract Pending', CloseDate=Date.newInstance(2026,10,31), Start_Date__c=Date.newInstance(2026,9,1),  End_Date__c=Date.newInstance(2026,11,30), Amount=19550,  Market__c='San Diego',   Description='CoxReps — Strategic Media Services. Political Advocacy, RA35+. [TV-Linear]'),
    new Opportunity(Name='DBG 4U Realty Plus — Phoenix TV Linear Q4 2026',     AccountId=advIds.get('4U Realty Plus, LLC'),            StageName='Stage 2 - Discovery/CNA',   CloseDate=Date.newInstance(2026,10,31), Start_Date__c=Date.newInstance(2026,10,1), End_Date__c=Date.newInstance(2026,12,31), Amount=9885,   Market__c='Phoenix',     Description='Strata — David Acosta. Phoenix TV upsell discussion. [TV-Linear]'),
    new Opportunity(Name='DBG AdventHealth — Orlando Radio Q1 2026',           AccountId=advIds.get('AdventHealth'),                   StageName='Closed Won',                CloseDate=Date.newInstance(2026,1,15),  Start_Date__c=Date.newInstance(2026,1,1),  End_Date__c=Date.newInstance(2026,3,31),  Amount=14890,  Market__c='Orlando',     Description='Strata — Brown Parker & DeMarinis. Radio companion to TV Q1 flight. [Radio-Linear]')
};
Database.SaveResult[] or2 = Database.insert(opps, false);
List<Opportunity> goodOpps = new List<Opportunity>();
for (Integer i = 0; i < or2.size(); i++) {
    if (or2[i].isSuccess()) {
        goodOpps.add(opps[i]);
        System.debug('  OK opp[' + i + ']: ' + opps[i].Name);
    } else {
        System.debug('  FAIL opp[' + i + '] ' + opps[i].Name + ': ' + or2[i].getErrors()[0].getMessage() + ' fields=' + or2[i].getErrors()[0].getFields());
    }
}

// Cleanup
System.debug('=== CLEANUP ===');
if (!goodOpps.isEmpty()) { delete goodOpps; System.debug('  Deleted ' + goodOpps.size() + ' opps'); }
List<Account> allAccts = new List<Account>();
allAccts.addAll(agencies);
allAccts.addAll(advertisers);
delete allAccts;
System.debug('  Deleted ' + allAccts.size() + ' accounts');
