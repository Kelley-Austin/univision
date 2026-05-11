// Minimal Opportunity to isolate the validation
Opportunity o = new Opportunity(
    Name='TEST MINIMAL OPP - DELETE ME',
    StageName='Stage 1 - Lead',
    CloseDate=Date.newInstance(2026,12,31)
);
try {
    insert o;
    System.debug('SUCCESS - inserted: ' + o.Id);
    // Clean up immediately
    delete o;
    System.debug('CLEANUP done');
} catch (DmlException e) {
    System.debug('ERROR: ' + e.getMessage());
    System.debug('FIELDS: ' + e.getDmlFields(0));
}
