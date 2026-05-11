// Use an existing account
Account a = [SELECT Id FROM Account WHERE Name = 'Edge Communications' LIMIT 1];

Opportunity o = new Opportunity(
    Name='TEST JEEP ACCT - DELETE ME',
    AccountId=a.Id,
    StageName='Stage 3 - Pipeline/Deal',
    CloseDate=Date.newInstance(2026,9,30),
    Start_Date__c=Date.newInstance(2026,7,1),
    End_Date__c=Date.newInstance(2026,9,30),
    Amount=55000,
    Market__c='Detroit',
    Description='Test with account'
);
try {
    insert o;
    System.debug('SUCCESS: ' + o.Id);
    delete o;
} catch (DmlException e) {
    System.debug('FAIL: ' + e.getDmlMessage(0));
    System.debug('FIELDS: ' + e.getDmlFields(0));
}

// Also test: does creating new account in same transaction then using it on opp work?
Account newAcct = new Account(Name='TEST ACCT TEMP', RecordTypeId='012NS00000CTRNhYAP');
insert newAcct;
Opportunity o2 = new Opportunity(
    Name='TEST FRESH ACCT OPP - DELETE ME',
    AccountId=newAcct.Id,
    StageName='Stage 3 - Pipeline/Deal',
    CloseDate=Date.newInstance(2026,9,30),
    Start_Date__c=Date.newInstance(2026,7,1),
    End_Date__c=Date.newInstance(2026,9,30),
    Amount=55000,
    Market__c='Detroit'
);
try {
    insert o2;
    System.debug('NEW ACCT OPP SUCCESS: ' + o2.Id);
    delete o2;
} catch (DmlException e) {
    System.debug('NEW ACCT OPP FAIL: ' + e.getDmlMessage(0));
}
delete newAcct;
