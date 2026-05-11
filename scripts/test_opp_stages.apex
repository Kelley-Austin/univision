List<String> stages = new List<String>{
    'Stage 1 - Lead',
    'Stage 2 - Discovery/CNA',
    'Stage 3 - Pipeline/Deal',
    'Stage 4 - Negotiation',
    'Stage 5 - Contract Pending',
    'Closed Won'
};
List<Opportunity> toDelete = new List<Opportunity>();
for (String s : stages) {
    Opportunity o = new Opportunity(
        Name='TEST STAGE ' + s + ' - DELETE ME',
        StageName=s,
        CloseDate=Date.newInstance(2026,12,31),
        Start_Date__c=Date.newInstance(2026,1,1),
        End_Date__c=Date.newInstance(2026,12,31),
        Amount=10000,
        Market__c='Detroit'
    );
    try {
        insert o;
        System.debug('OK: ' + s);
        toDelete.add(o);
    } catch (DmlException e) {
        System.debug('FAIL [' + s + ']: ' + e.getDmlMessage(0));
    }
}
if (!toDelete.isEmpty()) delete toDelete;
System.debug('Cleaned up ' + toDelete.size() + ' test opps');
