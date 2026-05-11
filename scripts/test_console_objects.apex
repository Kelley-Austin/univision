// Test field access on the console-related objects
// Source_System__c
Source_System__c ss = new Source_System__c(
    Name='TEST WideOrbit',
    Code__c='WO_TV',
    Is_Active__c=true
);
try { insert ss; System.debug('Source_System__c OK: ' + ss.Id); delete ss; }
catch(Exception e) { System.debug('Source_System__c FAIL: ' + e.getMessage()); }

// Load_Batch__c - needs Source_System__c first, test schema access only
Load_Batch__c lb = new Load_Batch__c();
lb.Name = 'TEST Batch';
try { lb.put('File_Name__c', 'test.csv'); System.debug('Load_Batch put OK'); }
catch(Exception e) { System.debug('Load_Batch put FAIL: ' + e.getMessage()); }

// Pacing_Snapshot__c
Pacing_Snapshot__c ps = new Pacing_Snapshot__c();
try { ps.put('Booked_Amount__c', 100000); System.debug('Pacing_Snapshot put OK'); }
catch(Exception e) { System.debug('Pacing_Snapshot put FAIL: ' + e.getMessage()); }

// Inbound_Staging__c
Inbound_Staging__c ist = new Inbound_Staging__c();
try { ist.put('Status__c', 'Unmatched'); System.debug('Inbound_Staging put OK'); }
catch(Exception e) { System.debug('Inbound_Staging put FAIL: ' + e.getMessage()); }
