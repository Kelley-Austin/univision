// ── Seed Test Data ─────────────────────────────────────────────────────────
// Advertisers, Agencies, Opportunities, Contracts, Channels, Budget Lines
// Sourced from CoxReps + Strata client artifact files.
// Uses Database.insert with partial success so individual failures don't abort
// the whole run.
// ───────────────────────────────────────────────────────────────────────────

Id rtAdvertiser = '012NS00000CTRNhYAP';
Id rtAgency     = '012NS00000CTRNiYAP';

Integer totalOk   = 0;
Integer totalFail = 0;

// ── Helper to log DML results ────────────────────────────────────────────────
void logResults(String label, List<Database.SaveResult> results, List<String> names) {
    for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
            System.debug('[OK] ' + label + '[' + i + '] ' + names[i] + ' → ' + results[i].getId());
            totalOk++;
        } else {
            System.debug('[FAIL] ' + label + '[' + i + '] ' + names[i] + ': ' + results[i].getErrors()[0].getMessage() + ' fields=' + results[i].getErrors()[0].getFields());
            totalFail++;
        }
    }
}

// ── 1. Agency Accounts ──────────────────────────────────────────────────────
List<Account> agencies = new List<Account>{
    new Account(Name='Starcom Media Services',       RecordTypeId=rtAgency, Phone='312-220-3500'),
    new Account(Name='Carat USA, Inc.',              RecordTypeId=rtAgency, Phone='212-591-9200'),
    new Account(Name='Brown Parker & DeMarinis',     RecordTypeId=rtAgency, Phone='407-843-6000'),
    new Account(Name='Strategic Media Services',     RecordTypeId=rtAgency, Phone='703-524-4000')
};
List<String> agencyNames = new List<String>{'Starcom Media Services','Carat USA, Inc.','Brown Parker & DeMarinis','Strategic Media Services'};
Database.SaveResult[] agencyResults = Database.insert(agencies, false);
logResults('Agency', agencyResults, agencyNames);
Map<String,Id> agencyIds = new Map<String,Id>();
for (Account a : agencies) if (a.Id != null) agencyIds.put(a.Name, a.Id);

// ── 2. Advertiser Accounts ──────────────────────────────────────────────────
List<Account> advertisers = new List<Account>{
    new Account(Name='Jeep Retail Corp.',              RecordTypeId=rtAdvertiser, Industry='Automotive',     Phone='248-576-5741'),
    new Account(Name='Ram Truck Retail Corp',          RecordTypeId=rtAdvertiser, Industry='Automotive',     Phone='248-576-5000'),
    new Account(Name='Jack in the Box Inc.',           RecordTypeId=rtAdvertiser, Industry='Food & Beverage',Phone='858-571-2121'),
    new Account(Name='Ultimate Fighting Championship', RecordTypeId=rtAdvertiser, Industry='Entertainment',  Phone='702-432-2440'),
    new Account(Name='4U Realty Plus, LLC',            RecordTypeId=rtAdvertiser, Industry='Real Estate',    Phone='602-555-0181'),
    new Account(Name='AdventHealth',                   RecordTypeId=rtAdvertiser, Industry='Healthcare',     Phone='407-303-5600'),
    new Account(Name='AdsWizz, Inc.',                  RecordTypeId=rtAdvertiser, Industry='Technology',     Phone='650-555-0122'),
    new Account(Name='Dept. of Homeland Security',     RecordTypeId=rtAdvertiser, Industry='Government',     Phone='202-282-8000')
};
List<String> advNames = new List<String>{'Jeep Retail Corp.','Ram Truck Retail Corp','Jack in the Box Inc.','Ultimate Fighting Championship','4U Realty Plus, LLC','AdventHealth','AdsWizz, Inc.','Dept. of Homeland Security'};
Database.SaveResult[] advResults = Database.insert(advertisers, false);
logResults('Advertiser', advResults, advNames);
Map<String,Id> advIds = new Map<String,Id>();
for (Account a : advertisers) if (a.Id != null) advIds.put(a.Name, a.Id);

// ── 3. Opportunities ────────────────────────────────────────────────────────
// RecordTypeId omitted — custom RTs not yet assigned to System Admin profile.
List<Opportunity> opps = new List<Opportunity>{
    new Opportunity(
        Name='Jeep Retail Corp. — EUVF TV Q3 2026',
        AccountId=advIds.get('Jeep Retail Corp.'),
        StageName='Stage 3 - Pipeline/Deal',
        CloseDate=Date.newInstance(2026,9,30),
        Start_Date__c=Date.newInstance(2026,7,1),
        End_Date__c=Date.newInstance(2026,9,30),
        Amount=55000,
        Market__c='Detroit',
        Description='CoxReps — TeleRep Sun Broadcasting, EUVF. A25-54 Time Sale. [TV-Linear]'
    ),
    new Opportunity(
        Name='Jeep Retail Corp. — Digital Display Q4 2026',
        AccountId=advIds.get('Jeep Retail Corp.'),
        StageName='Stage 4 - Negotiation',
        CloseDate=Date.newInstance(2026,11,15),
        Start_Date__c=Date.newInstance(2026,10,1),
        End_Date__c=Date.newInstance(2026,12,31),
        Amount=28500,
        Market__c='Detroit',
        Description='CoxReps — Digital extension of EUVF buy. [Digital]'
    ),
    new Opportunity(
        Name='Ram Truck Retail Corp — EUVF TV Q3 2026',
        AccountId=advIds.get('Ram Truck Retail Corp'),
        StageName='Stage 5 - Contract Pending',
        CloseDate=Date.newInstance(2026,8,31),
        Start_Date__c=Date.newInstance(2026,7,1),
        End_Date__c=Date.newInstance(2026,9,30),
        Amount=41750,
        Market__c='Detroit',
        Description='CoxReps — TeleRep Sun Broadcasting, EUVF. A25-54 & RA35+. [TV-Linear]'
    ),
    new Opportunity(
        Name='Jack in the Box Inc. — KBNT Radio Q3 2026',
        AccountId=advIds.get('Jack in the Box Inc.'),
        StageName='Stage 2 - Discovery/CNA',
        CloseDate=Date.newInstance(2026,9,30),
        Start_Date__c=Date.newInstance(2026,7,1),
        End_Date__c=Date.newInstance(2026,9,30),
        Amount=12000,
        Market__c='San Diego',
        Description='CoxReps — Carat USA. QSR fastfood flight, A25-54. [Radio-Linear]'
    ),
    new Opportunity(
        Name='UFC — KBNT Digital 2026',
        AccountId=advIds.get('Ultimate Fighting Championship'),
        StageName='Stage 3 - Pipeline/Deal',
        CloseDate=Date.newInstance(2026,10,31),
        Start_Date__c=Date.newInstance(2026,9,1),
        End_Date__c=Date.newInstance(2026,12,31),
        Amount=25000,
        Market__c='Minneapolis',
        Description='CoxReps — JSML Media LLC. RM21-49 demo. [Digital]'
    ),
    new Opportunity(
        Name='AdventHealth — Orlando DIG TV Q1 2026',
        AccountId=advIds.get('AdventHealth'),
        StageName='Closed Won',
        CloseDate=Date.newInstance(2026,1,31),
        Start_Date__c=Date.newInstance(2026,1,1),
        End_Date__c=Date.newInstance(2026,3,31),
        Amount=16182,
        Market__c='Orlando',
        Description='Strata — Brown Parker & DeMarinis. AdventHealth healthcare Q1 flight. [TV-Linear]'
    ),
    new Opportunity(
        Name='AdventHealth — Orlando DIG TV Q2-Q3 2026',
        AccountId=advIds.get('AdventHealth'),
        StageName='Stage 4 - Negotiation',
        CloseDate=Date.newInstance(2026,5,31),
        Start_Date__c=Date.newInstance(2026,4,1),
        End_Date__c=Date.newInstance(2026,9,30),
        Amount=35892,
        Market__c='Orlando',
        Description='Strata — Brown Parker & DeMarinis. AdventHealth renewal Q2-Q3. [TV-Linear]'
    ),
    new Opportunity(
        Name='AdsWizz, Inc. — Corporate TV Digital 2026',
        AccountId=advIds.get('AdsWizz, Inc.'),
        StageName='Stage 1 - Lead',
        CloseDate=Date.newInstance(2026,6,30),
        Start_Date__c=Date.newInstance(2026,1,1),
        End_Date__c=Date.newInstance(2026,6,30),
        Amount=291751,
        Market__c='Corporate',
        Description='Strata — NoAE Local. AdsWizz programmatic streaming. H1 2026. [Digital]'
    ),
    new Opportunity(
        Name='4U Realty Plus — Phoenix Radio Digital 2026',
        AccountId=advIds.get('4U Realty Plus, LLC'),
        StageName='Stage 3 - Pipeline/Deal',
        CloseDate=Date.newInstance(2026,9,30),
        Start_Date__c=Date.newInstance(2026,4,1),
        End_Date__c=Date.newInstance(2026,12,31),
        Amount=38955,
        Market__c='Phoenix',
        Description='Strata — David Acosta. Local Phoenix DIG, Real Estate Agents category. [Radio-Digital]'
    ),
    new Opportunity(
        Name='Dept. of Homeland Security — KBNT TV Political',
        AccountId=advIds.get('Dept. of Homeland Security'),
        StageName='Stage 5 - Contract Pending',
        CloseDate=Date.newInstance(2026,10,31),
        Start_Date__c=Date.newInstance(2026,9,1),
        End_Date__c=Date.newInstance(2026,11,30),
        Amount=19550,
        Market__c='San Diego',
        Description='CoxReps — Strategic Media Services. Political Advocacy, RA35+. [TV-Linear]'
    ),
    new Opportunity(
        Name='4U Realty Plus — Phoenix TV Linear Q4 2026',
        AccountId=advIds.get('4U Realty Plus, LLC'),
        StageName='Stage 2 - Discovery/CNA',
        CloseDate=Date.newInstance(2026,10,31),
        Start_Date__c=Date.newInstance(2026,10,1),
        End_Date__c=Date.newInstance(2026,12,31),
        Amount=9885,
        Market__c='Phoenix',
        Description='Strata — David Acosta. Phoenix TV upsell discussion. [TV-Linear]'
    ),
    new Opportunity(
        Name='AdventHealth — Orlando Radio Q1 2026',
        AccountId=advIds.get('AdventHealth'),
        StageName='Closed Won',
        CloseDate=Date.newInstance(2026,1,15),
        Start_Date__c=Date.newInstance(2026,1,1),
        End_Date__c=Date.newInstance(2026,3,31),
        Amount=14890,
        Market__c='Orlando',
        Description='Strata — Brown Parker & DeMarinis. Radio companion to TV Q1 flight. [Radio-Linear]'
    )
};
List<String> oppNames = new List<String>{
    'Jeep Retail Corp. — EUVF TV Q3 2026','Jeep Retail Corp. — Digital Display Q4 2026',
    'Ram Truck Retail Corp — EUVF TV Q3 2026','Jack in the Box Inc. — KBNT Radio Q3 2026',
    'UFC — KBNT Digital 2026','AdventHealth — Orlando DIG TV Q1 2026',
    'AdventHealth — Orlando DIG TV Q2-Q3 2026','AdsWizz, Inc. — Corporate TV Digital 2026',
    '4U Realty Plus — Phoenix Radio Digital 2026','Dept. of Homeland Security — KBNT TV Political',
    '4U Realty Plus — Phoenix TV Linear Q4 2026','AdventHealth — Orlando Radio Q1 2026'
};
Database.SaveResult[] oppResults = Database.insert(opps, false);
logResults('Opportunity', oppResults, oppNames);
Map<String,Id> oppIds = new Map<String,Id>();
for (Opportunity o : opps) if (o.Id != null) oppIds.put(o.Name, o.Id);

// ── 4. Advertising Contracts ────────────────────────────────────────────────
List<Advertising_Contract__c> contracts = new List<Advertising_Contract__c>{
    new Advertising_Contract__c(
        Opportunity__c=oppIds.get('AdventHealth — Orlando DIG TV Q1 2026'),
        Contract_Status__c='Active'
    ),
    new Advertising_Contract__c(
        Opportunity__c=oppIds.get('AdventHealth — Orlando Radio Q1 2026'),
        Contract_Status__c='Completed'
    ),
    new Advertising_Contract__c(
        Opportunity__c=oppIds.get('Jeep Retail Corp. — Digital Display Q4 2026'),
        Contract_Status__c='Draft'
    ),
    new Advertising_Contract__c(
        Opportunity__c=oppIds.get('Ram Truck Retail Corp — EUVF TV Q3 2026'),
        Contract_Status__c='Approved'
    ),
    new Advertising_Contract__c(
        Opportunity__c=oppIds.get('Dept. of Homeland Security — KBNT TV Political'),
        Contract_Status__c='Pending Approval'
    ),
    new Advertising_Contract__c(
        Opportunity__c=oppIds.get('AdventHealth — Orlando DIG TV Q2-Q3 2026'),
        Contract_Status__c='Draft'
    )
};
List<String> contractNames = new List<String>{
    'AdventHealth TV Q1 - Active','AdventHealth Radio Q1 - Completed',
    'Jeep Digital Q4 - Draft','Ram Truck TV Q3 - Approved',
    'DHS TV Political - Pending Approval','AdventHealth TV Q2-Q3 - Draft'
};
Database.SaveResult[] contractResults = Database.insert(contracts, false);
logResults('Contract', contractResults, contractNames);

// ── 5. Channel Records ──────────────────────────────────────────────────────
List<Channel__c> channels = new List<Channel__c>{
    new Channel__c(Name='TV - Local Broadcast',      Status__c='Active'),
    new Channel__c(Name='TV - National/Affiliate',   Status__c='Active'),
    new Channel__c(Name='Radio - AM/FM Linear',      Status__c='Active'),
    new Channel__c(Name='Radio - Digital Streaming', Status__c='Active'),
    new Channel__c(Name='Digital Display',           Status__c='Active')
};
List<String> channelNames = new List<String>{'TV - Local Broadcast','TV - National/Affiliate','Radio - AM/FM Linear','Radio - Digital Streaming','Digital Display'};
Database.SaveResult[] chResults = Database.insert(channels, false);
logResults('Channel', chResults, channelNames);
Map<String,Id> chIds = new Map<String,Id>();
for (Channel__c c : channels) if (c.Id != null) chIds.put(c.Name, c.Id);

// ── 6. Budget Lines ─────────────────────────────────────────────────────────
// Date_Type__c, Calendar_Date__c, Broadcast_Date__c exist in the org schema but
// are not yet in compiled Apex; use put() for dynamic field assignment.
Map<String,Object> blBase = new Map<String,Object>{
    'Date_Type__c'     => 'Calendar',
    'Calendar_Date__c' => Date.newInstance(2026, 7, 1)
};
List<Budget_Line__c> budgetLines = new List<Budget_Line__c>();
List<Map<String,Object>> blDefs = new List<Map<String,Object>>{
    new Map<String,Object>{'Account__c'=>advIds.get('Jeep Retail Corp.'),              'Channel__c'=>chIds.get('TV - Local Broadcast'),      'Status__c'=>'Approved'},
    new Map<String,Object>{'Account__c'=>advIds.get('Jeep Retail Corp.'),              'Channel__c'=>chIds.get('Digital Display'),            'Status__c'=>'Draft'},
    new Map<String,Object>{'Account__c'=>advIds.get('Ram Truck Retail Corp'),          'Channel__c'=>chIds.get('TV - Local Broadcast'),       'Status__c'=>'Approved'},
    new Map<String,Object>{'Account__c'=>advIds.get('Jack in the Box Inc.'),           'Channel__c'=>chIds.get('Radio - AM/FM Linear'),       'Status__c'=>'Draft'},
    new Map<String,Object>{'Account__c'=>advIds.get('Ultimate Fighting Championship'), 'Channel__c'=>chIds.get('Digital Display'),            'Status__c'=>'Draft'},
    new Map<String,Object>{'Account__c'=>advIds.get('AdventHealth'),                   'Channel__c'=>chIds.get('TV - Local Broadcast'),       'Status__c'=>'Locked'},
    new Map<String,Object>{'Account__c'=>advIds.get('AdventHealth'),                   'Channel__c'=>chIds.get('Radio - AM/FM Linear'),       'Status__c'=>'Locked'},
    new Map<String,Object>{'Account__c'=>advIds.get('AdsWizz, Inc.'),                  'Channel__c'=>chIds.get('Digital Display'),            'Status__c'=>'Draft'},
    new Map<String,Object>{'Account__c'=>advIds.get('4U Realty Plus, LLC'),            'Channel__c'=>chIds.get('Radio - Digital Streaming'),  'Status__c'=>'Approved'},
    new Map<String,Object>{'Account__c'=>advIds.get('Dept. of Homeland Security'),     'Channel__c'=>chIds.get('TV - National/Affiliate'),    'Status__c'=>'Approved'}
};
for (Map<String,Object> def : blDefs) {
    Budget_Line__c bl = new Budget_Line__c();
    for (String k : blBase.keySet())  bl.put(k, blBase.get(k));
    for (String k : def.keySet())     bl.put(k, def.get(k));
    budgetLines.add(bl);
}
List<String> blNames = new List<String>{
    'Jeep/TV-Local','Jeep/Digital','Ram Truck/TV-Local','JitB/Radio-Linear',
    'UFC/Digital','AdventHealth/TV-Local','AdventHealth/Radio-Linear',
    'AdsWizz/Digital','4U Realty/Radio-Digital','DHS/TV-National'
};
Database.SaveResult[] blResults = Database.insert(budgetLines, false);
logResults('BudgetLine', blResults, blNames);

// ── Summary ──────────────────────────────────────────────────────────────────
System.debug('');
System.debug('=== SEED SUMMARY ===');
System.debug('Total OK:   ' + totalOk);
System.debug('Total FAIL: ' + totalFail);
