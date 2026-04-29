public with sharing class ExclusionLogController {

    public class ExclusionRow {
        @AuraEnabled public String  stagingId         { get; set; }
        @AuraEnabled public String  externalKey       { get; set; }
        @AuraEnabled public String  rawAdvertiserName { get; set; }
        @AuraEnabled public String  rawAdvertiserCode { get; set; }
        @AuraEnabled public Decimal revenueAmount     { get; set; }
        @AuraEnabled public String  revenueType       { get; set; }
        @AuraEnabled public Integer periodYear        { get; set; }
        @AuraEnabled public Integer periodMonth       { get; set; }
        @AuraEnabled public String  excludingRule     { get; set; }
        @AuraEnabled public String  sourceSystem      { get; set; }
        @AuraEnabled public String  createdDate       { get; set; }
    }

    // ── List excluded staging rows with optional filters ──────────────────────

    @AuraEnabled(cacheable=false)
    public static List<ExclusionRow> getExcludedRows(
        Integer pageSize, Integer pageOffset,
        String excludingRule, Integer periodYear
    ) {
        Integer lim = (pageSize   != null && pageSize   > 0) ? Math.min(pageSize, 200) : 50;
        Integer off = (pageOffset != null && pageOffset > 0) ? pageOffset               : 0;

        String q = 'SELECT Id, External_Key__c, Raw_Advertiser_Name__c, '
                 + '  Raw_Advertiser_Code__c, Revenue_Amount__c, Revenue_Type__c, '
                 + '  Period_Year__c, Period_Month__c, Excluding_Rule__c, '
                 + '  Source_System__r.Name, CreatedDate '
                 + 'FROM Inbound_Staging__c '
                 + 'WHERE Status__c = \'Excluded\' ';
        if (String.isNotBlank(excludingRule)) {
            q += 'AND Excluding_Rule__c = \'' + String.escapeSingleQuotes(excludingRule) + '\' ';
        }
        if (periodYear != null) {
            q += 'AND Period_Year__c = ' + periodYear + ' ';
        }
        q += 'ORDER BY CreatedDate DESC LIMIT ' + lim + ' OFFSET ' + off;

        List<ExclusionRow> rows = new List<ExclusionRow>();
        for (Inbound_Staging__c stg : (List<Inbound_Staging__c>) Database.query(q)) {
            ExclusionRow row = new ExclusionRow();
            row.stagingId         = stg.Id;
            row.externalKey       = stg.External_Key__c;
            row.rawAdvertiserName = stg.Raw_Advertiser_Name__c;
            row.rawAdvertiserCode = stg.Raw_Advertiser_Code__c;
            row.revenueAmount     = stg.Revenue_Amount__c;
            row.revenueType       = stg.Revenue_Type__c;
            row.periodYear        = stg.Period_Year__c  != null ? stg.Period_Year__c.intValue()  : null;
            row.periodMonth       = stg.Period_Month__c != null ? stg.Period_Month__c.intValue() : null;
            row.excludingRule     = stg.Excluding_Rule__c;
            row.sourceSystem      = stg.Source_System__r != null ? stg.Source_System__r.Name : '';
            row.createdDate       = stg.CreatedDate != null
                ? stg.CreatedDate.format('MMM d, yyyy') : '';
            rows.add(row);
        }
        return rows;
    }

    // ── Re-queue selected exclusions back to Pending for re-reconciliation ────

    @AuraEnabled
    public static void requeueRows(List<Id> stagingIds) {
        if (stagingIds == null || stagingIds.isEmpty()) { return; }
        List<Inbound_Staging__c> toUpdate = new List<Inbound_Staging__c>();
        for (Id sid : stagingIds) {
            toUpdate.add(new Inbound_Staging__c(
                Id              = sid,
                Status__c       = 'Pending',
                Excluding_Rule__c = null
            ));
        }
        update toUpdate;
    }

    // ── Distinct exclusion rule tokens present in the data ────────────────────

    @AuraEnabled(cacheable=true)
    public static List<String> getExclusionRuleOptions() {
        List<String> rules = new List<String>{ '' };
        for (AggregateResult ar : [
            SELECT Excluding_Rule__c rule
            FROM   Inbound_Staging__c
            WHERE  Status__c          = 'Excluded'
              AND  Excluding_Rule__c != null
            GROUP BY Excluding_Rule__c
            ORDER BY COUNT(Id) DESC
            LIMIT  30
        ]) {
            rules.add((String) ar.get('rule'));
        }
        return rules;
    }
}
