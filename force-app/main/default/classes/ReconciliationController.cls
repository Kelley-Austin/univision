/**
 * Apex controller backing both reconciliation worklist LWCs.
 *
 * aeReconciliationWorklist  — filters by AE user, shows current user's unmatched rows
 * salesOpsReconciliationWorklist — shows all unmatched rows with cross-AE filter
 *
 * All write operations (acceptMatch, excludeRow) trigger a mini-reconcile on the
 * single row and re-evaluate Is_Late / Category_Snapshot via normal trigger.
 */
public with sharing class ReconciliationController {

    // ── Inner types ───────────────────────────────────────────────────────────

    public class WorklistRow {
        @AuraEnabled public Id     stagingId          { get; set; }
        @AuraEnabled public String rawAdvertiserName  { get; set; }
        @AuraEnabled public String rawAdvertiserCode  { get; set; }
        @AuraEnabled public String rawAeCode          { get; set; }
        @AuraEnabled public Decimal revenueAmount     { get; set; }
        @AuraEnabled public Integer periodMonth       { get; set; }
        @AuraEnabled public Integer periodYear        { get; set; }
        @AuraEnabled public String revenueType        { get; set; }
        @AuraEnabled public String sourceSystem       { get; set; }
        @AuraEnabled public Integer matchAccountTier  { get; set; }
        @AuraEnabled public Integer matchAeTier       { get; set; }
        @AuraEnabled public List<AccountMatcher.MatchSuggestion> suggestions { get; set; }
        public WorklistRow() {
            suggestions = new List<AccountMatcher.MatchSuggestion>();
        }
    }

    public class WorklistResult {
        @AuraEnabled public List<WorklistRow> rows       { get; set; }
        @AuraEnabled public Integer           totalCount { get; set; }
        public WorklistResult() {
            rows = new List<WorklistRow>();
        }
    }

    // ── AE-scoped worklist ────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static WorklistResult getAeWorklist(
        Id aeUserId, Integer pageSize, Integer pageOffset
    ) {
        if (pageSize == null || pageSize <= 0)  pageSize  = 50;
        if (pageOffset == null || pageOffset < 0) pageOffset = 0;
        if (aeUserId == null) aeUserId = UserInfo.getUserId();

        List<Inbound_Staging__c> rows = [
            SELECT Id, Raw_Advertiser_Name__c, Raw_Advertiser_Code__c,
                   Raw_Salesperson_Code__c, Revenue_Amount__c,
                   Period_Month__c, Period_Year__c, Revenue_Type__c,
                   Match_Account_Tier__c, Match_AE_Tier__c,
                   Source_System__r.Name
            FROM   Inbound_Staging__c
            WHERE  Status__c  = 'Unmatched'
              AND  AE_User__c = :aeUserId
            ORDER BY CreatedDate DESC
            LIMIT  :pageSize
            OFFSET :pageOffset
        ];

        Integer total = [
            SELECT COUNT() FROM Inbound_Staging__c
            WHERE Status__c = 'Unmatched' AND AE_User__c = :aeUserId
        ];

        return buildResult(rows, total);
    }

    // ── Sales Ops bulk worklist ───────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static WorklistResult getSalesOpsWorklist(
        Id filterAeUserId,
        String filterSourceSystem,
        Integer filterMonth,
        Integer filterYear,
        Integer pageSize,
        Integer pageOffset
    ) {
        if (pageSize == null || pageSize <= 0)    pageSize   = 100;
        if (pageOffset == null || pageOffset < 0) pageOffset = 0;

        String q = 'SELECT Id, Raw_Advertiser_Name__c, Raw_Advertiser_Code__c, '
                 + '  Raw_Salesperson_Code__c, Revenue_Amount__c, '
                 + '  Period_Month__c, Period_Year__c, Revenue_Type__c, '
                 + '  Match_Account_Tier__c, Match_AE_Tier__c, '
                 + '  Source_System__r.Name '
                 + 'FROM Inbound_Staging__c '
                 + 'WHERE Status__c = \'Unmatched\' ';

        if (filterAeUserId != null) {
            q += ' AND AE_User__c = \'' + String.escapeSingleQuotes(filterAeUserId) + '\'';
        }
        if (String.isNotBlank(filterSourceSystem)) {
            q += ' AND Source_System__r.Code__c = \'' + String.escapeSingleQuotes(filterSourceSystem) + '\'';
        }
        if (filterMonth != null && filterMonth > 0) {
            q += ' AND Period_Month__c = ' + filterMonth;
        }
        if (filterYear != null && filterYear > 0) {
            q += ' AND Period_Year__c = ' + filterYear;
        }
        q += ' ORDER BY CreatedDate DESC LIMIT ' + pageSize + ' OFFSET ' + pageOffset;

        List<Inbound_Staging__c> rows = Database.query(q);

        String countQ = 'SELECT COUNT() FROM Inbound_Staging__c WHERE Status__c = \'Unmatched\'';
        if (filterAeUserId != null) {
            countQ += ' AND AE_User__c = \'' + String.escapeSingleQuotes(filterAeUserId) + '\'';
        }
        if (String.isNotBlank(filterSourceSystem)) {
            countQ += ' AND Source_System__r.Code__c = \'' + String.escapeSingleQuotes(filterSourceSystem) + '\'';
        }
        if (filterMonth != null && filterMonth > 0) {
            countQ += ' AND Period_Month__c = ' + filterMonth;
        }
        if (filterYear != null && filterYear > 0) {
            countQ += ' AND Period_Year__c = ' + filterYear;
        }
        Integer total = Database.countQuery(countQ);

        return buildResult(rows, total);
    }

    // ── Accept a match suggestion ─────────────────────────────────────────────

    @AuraEnabled
    public static String acceptMatch(Id stagingId, Id accountId, Integer tier) {
        Inbound_Staging__c row = getStagingRow(stagingId);
        if (row == null) return 'Error: staging row not found';

        row.Account__c            = accountId;
        row.Match_Account_Tier__c = tier;
        row.Status__c             = 'Matched';

        Actual_Revenue__c actual = new Actual_Revenue__c(
            External_Key__c   = row.External_Key__c,
            Account__c        = accountId,
            Revenue_Amount__c = row.Revenue_Amount__c,
            Revenue_Type__c   = row.Revenue_Type__c,
            Period_Month__c   = row.Period_Month__c,
            Period_Year__c    = row.Period_Year__c,
            Station_Code__c   = row.Station_Code__c,
            AE_Code__c        = row.Raw_Salesperson_Code__c,
            Broadcast_Period__c = row.Broadcast_Period__c,
            Source_System__c  = row.Source_System__c,
            Inbound_Staging__c = row.Id
        );

        try {
            upsert actual Actual_Revenue__c.External_Key__c;
            update row;
            return 'success';
        } catch (Exception ex) {
            return 'Error: ' + ex.getMessage();
        }
    }

    // ── Exclude a row ─────────────────────────────────────────────────────────

    @AuraEnabled
    public static String excludeRow(Id stagingId, String reason) {
        Inbound_Staging__c row = getStagingRow(stagingId);
        if (row == null) return 'Error: staging row not found';

        row.Status__c         = 'Excluded';
        row.Excluding_Rule__c = String.isNotBlank(reason) ? reason.abbreviate(255) : 'MANUAL_EXCLUDE';

        try {
            update row;
            return 'success';
        } catch (Exception ex) {
            return 'Error: ' + ex.getMessage();
        }
    }

    // ── Live account search for manual pick ───────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<AccountMatcher.MatchSuggestion> searchAccounts(String term) {
        if (String.isBlank(term) || term.length() < 2) {
            return new List<AccountMatcher.MatchSuggestion>();
        }
        String soslTerm = String.escapeSingleQuotes(term.trim()) + '*';
        List<List<SObject>> results = Search.query(
            'FIND \'' + soslTerm + '\' IN NAME FIELDS '
            + 'RETURNING Account(Id, Name WHERE RecordType.DeveloperName = \'Advertiser\') LIMIT 10'
        );
        List<AccountMatcher.MatchSuggestion> suggestions = new List<AccountMatcher.MatchSuggestion>();
        for (SObject rec : results[0]) {
            Account acc = (Account) rec;
            AccountMatcher.MatchSuggestion s = new AccountMatcher.MatchSuggestion();
            s.accountId   = acc.Id;
            s.accountName = acc.Name;
            s.score       = 100;
            s.method      = 'MANUAL_SEARCH';
            suggestions.add(s);
        }
        return suggestions;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static WorklistResult buildResult(List<Inbound_Staging__c> rows, Integer total) {
        // Compute suggestions for all unmatched rows in one pass
        Set<String> names = new Set<String>();
        for (Inbound_Staging__c r : rows) {
            if (String.isNotBlank(r.Raw_Advertiser_Name__c)) names.add(r.Raw_Advertiser_Name__c.trim());
        }
        Map<String, List<AccountMatcher.MatchSuggestion>> suggMap =
            AccountMatcher.tier2FuzzyLookup(names);

        WorklistResult wr = new WorklistResult();
        wr.totalCount = total;
        for (Inbound_Staging__c r : rows) {
            WorklistRow row = new WorklistRow();
            row.stagingId         = r.Id;
            row.rawAdvertiserName = r.Raw_Advertiser_Name__c;
            row.rawAdvertiserCode = r.Raw_Advertiser_Code__c;
            row.rawAeCode         = r.Raw_Salesperson_Code__c;
            row.revenueAmount     = r.Revenue_Amount__c;
            row.periodMonth       = r.Period_Month__c != null ? r.Period_Month__c.intValue() : null;
            row.periodYear        = r.Period_Year__c  != null ? r.Period_Year__c.intValue()  : null;
            row.revenueType       = r.Revenue_Type__c;
            row.sourceSystem      = r.Source_System__r != null ? r.Source_System__r.Name : null;
            row.matchAccountTier  = r.Match_Account_Tier__c != null
                ? r.Match_Account_Tier__c.intValue() : null;
            row.matchAeTier       = r.Match_AE_Tier__c != null
                ? r.Match_AE_Tier__c.intValue() : null;

            String name = String.isNotBlank(r.Raw_Advertiser_Name__c) ? r.Raw_Advertiser_Name__c.trim() : null;
            if (name != null && suggMap.containsKey(name)) {
                row.suggestions = suggMap.get(name);
            }
            wr.rows.add(row);
        }
        return wr;
    }

    private static Inbound_Staging__c getStagingRow(Id stagingId) {
        List<Inbound_Staging__c> rows = [
            SELECT Id, External_Key__c, Status__c, Excluding_Rule__c,
                   Raw_Advertiser_Name__c, Raw_Advertiser_Code__c,
                   Raw_Salesperson_Code__c,
                   Revenue_Amount__c, Revenue_Type__c,
                   Period_Month__c, Period_Year__c,
                   Station_Code__c, Broadcast_Period__c,
                   Source_System__c, AE_User__c,
                   Account__c, Match_Account_Tier__c
            FROM   Inbound_Staging__c
            WHERE  Id = :stagingId
            LIMIT  1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
}
