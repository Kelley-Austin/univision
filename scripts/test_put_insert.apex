// Test whether put() + insert works for fields not in anonymous Apex schema
Integer ok = 0; Integer fail = 0;

// Source_System__c — Code__c, Is_Active__c not in schema but may work via put()
Source_System__c ss = new Source_System__c(Name='TEST WideOrbit PUT');
ss.put('Code__c', 'WO_TV');
ss.put('Is_Active__c', true);
ss.put('Source_Code__c', 'WO');
try {
    insert ss;
    System.debug('[OK] Source_System__c inserted: ' + ss.Id);
    ok++;
    // verify read-back
    Source_System__c ssBack = (Source_System__c)[SELECT Id FROM Source_System__c WHERE Id = :ss.Id];
    System.debug('[OK] Source_System__c queried back');
    delete ss;
} catch(Exception e) {
    System.debug('[FAIL] Source_System__c: ' + e.getMessage());
    fail++;
}

// Load_Batch__c — File_Name__c, Status__c, Row_Count__c not in schema (Name is auto-number)
Load_Batch__c lb = new Load_Batch__c();
lb.put('File_Name__c', 'WO_20260501.csv');
lb.put('Status__c', 'Complete');
lb.put('Row_Count__c', 250);
lb.put('Error_Count__c', 3);
try {
    insert lb;
    System.debug('[OK] Load_Batch__c inserted: ' + lb.Id);
    ok++;
    delete lb;
} catch(Exception e) {
    System.debug('[FAIL] Load_Batch__c: ' + e.getMessage());
    fail++;
}

// Pacing_Snapshot__c
Pacing_Snapshot__c ps = new Pacing_Snapshot__c();
ps.put('Booked_Amount__c', 1250000);
ps.put('Forecast_Amount__c', 1450000);
ps.put('Budget_Amount__c', 1600000);
ps.put('Period_Year__c', 2026);
ps.put('Period_Month__c', 5);
ps.put('Snapshot_Date__c', Date.today());
try {
    insert ps;
    System.debug('[OK] Pacing_Snapshot__c inserted: ' + ps.Id);
    ok++;
    delete ps;
} catch(Exception e) {
    System.debug('[FAIL] Pacing_Snapshot__c: ' + e.getMessage());
    fail++;
}

// Inbound_Staging__c
Inbound_Staging__c ist = new Inbound_Staging__c();
ist.put('Status__c', 'Unmatched');
ist.put('Revenue_Amount__c', 5000);
ist.put('Period_Year__c', 2026);
ist.put('Period_Month__c', 5);
try {
    insert ist;
    System.debug('[OK] Inbound_Staging__c inserted: ' + ist.Id);
    ok++;
    delete ist;
} catch(Exception e) {
    System.debug('[FAIL] Inbound_Staging__c: ' + e.getMessage());
    fail++;
}

System.debug('RESULT: ' + ok + ' OK / ' + fail + ' FAIL');
