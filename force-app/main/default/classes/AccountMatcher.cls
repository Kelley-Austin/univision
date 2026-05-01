/**
 * Three-tier account matcher for reconciling raw advertiser names/codes to
 * Salesforce Account records.
 *
 * Tier 1 — MDM External ID: exact match on Account.MDM_External_Id__c
 * Tier 2 — Fuzzy Name: SOSL + normalized Levenshtein scoring (≥70/100 required)
 * Tier 3 — Manual Queue: returns null accountId; caller surfaces up to 3 suggestions
 *
 * Usage (bulk):
 *   List<AccountMatcher.MatchResult> results = AccountMatcher.matchBulk(stagingRows);
 */
public with sharing class AccountMatcher {

    public static final Integer FUZZY_THRESHOLD    = 70;
    public static final Integer MAX_SUGGESTIONS    = 3;
    private static final String ADVERTISER_RT_NAME = 'Advertiser';

    // ── Public types ──────────────────────────────────────────────────────────

    public class MatchSuggestion {
        @AuraEnabled public Id      accountId   { get; set; }
        @AuraEnabled public String  accountName { get; set; }
        @AuraEnabled public Integer score       { get; set; }
        @AuraEnabled public String  method      { get; set; }
    }

    public class MatchResult {
        @AuraEnabled public Id                     accountId   { get; set; }
        @AuraEnabled public Integer                tier        { get; set; }
        @AuraEnabled public String                 method      { get; set; }
        @AuraEnabled public List<MatchSuggestion>  suggestions { get; set; }
        public MatchResult() {
            suggestions = new List<MatchSuggestion>();
        }
    }

    // ── Main bulk entry point ─────────────────────────────────────────────────

    /**
     * Match a batch of staging rows.  Returns one MatchResult per row, in the
     * same order as the input list.
     */
    public static List<MatchResult> matchBulk(List<Inbound_Staging__c> rows) {
        // Collect unique codes and names for bulk queries
        Set<String> rawCodes  = new Set<String>();
        Set<String> rawNames  = new Set<String>();
        for (Inbound_Staging__c row : rows) {
            if (String.isNotBlank(row.Raw_Advertiser_Code__c)) rawCodes.add(row.Raw_Advertiser_Code__c.trim());
            if (String.isNotBlank(row.Raw_Advertiser_Name__c)) rawNames.add(row.Raw_Advertiser_Name__c.trim());
        }

        // Tier 1: exact MDM ID lookup
        Map<String, Id> codeToAccount = tier1Lookup(rawCodes);

        // Tier 2: fuzzy name lookup for names that won't satisfy Tier 1
        // Build the set of names that still need matching after code lookup
        Set<String> unmatchedNames = new Set<String>();
        for (Inbound_Staging__c row : rows) {
            String code = String.isNotBlank(row.Raw_Advertiser_Code__c) ? row.Raw_Advertiser_Code__c.trim() : null;
            if (code == null || !codeToAccount.containsKey(code.toLowerCase())) {
                if (String.isNotBlank(row.Raw_Advertiser_Name__c)) {
                    unmatchedNames.add(row.Raw_Advertiser_Name__c.trim());
                }
            }
        }
        Map<String, List<MatchSuggestion>> nameSuggestions = tier2FuzzyLookup(unmatchedNames);

        // Build results
        List<MatchResult> results = new List<MatchResult>();
        for (Inbound_Staging__c row : rows) {
            MatchResult r = new MatchResult();

            String code = String.isNotBlank(row.Raw_Advertiser_Code__c) ? row.Raw_Advertiser_Code__c.trim() : null;
            if (code != null && codeToAccount.containsKey(code.toLowerCase())) {
                r.accountId = codeToAccount.get(code.toLowerCase());
                r.tier      = 1;
                r.method    = 'MDM_EXACT';
            } else {
                String name = String.isNotBlank(row.Raw_Advertiser_Name__c) ? row.Raw_Advertiser_Name__c.trim() : null;
                List<MatchSuggestion> suggestions = (name != null && nameSuggestions.containsKey(name))
                    ? nameSuggestions.get(name)
                    : new List<MatchSuggestion>();

                if (!suggestions.isEmpty() && suggestions[0].score >= FUZZY_THRESHOLD) {
                    r.accountId   = suggestions[0].accountId;
                    r.tier        = 2;
                    r.method      = 'FUZZY_NAME';
                    r.suggestions = suggestions;
                } else {
                    r.tier        = 3;
                    r.method      = 'MANUAL_QUEUE';
                    r.suggestions = suggestions; // up to MAX_SUGGESTIONS for worklist display
                }
            }
            results.add(r);
        }
        return results;
    }

    // ── Tier 1: MDM External ID ───────────────────────────────────────────────

    @TestVisible
    static Map<String, Id> tier1Lookup(Set<String> codes) {
        Map<String, Id> result = new Map<String, Id>();
        if (codes.isEmpty()) return result;
        for (Account acc : [
            SELECT Id, MDM_External_Id__c
            FROM   Account
            WHERE  MDM_External_Id__c IN :codes
              AND  RecordType.DeveloperName = :ADVERTISER_RT_NAME
        ]) {
            result.put(acc.MDM_External_Id__c.toLowerCase(), acc.Id);
        }
        return result;
    }

    // ── Tier 2: Fuzzy Name ────────────────────────────────────────────────────

    @TestVisible
    public static Map<String, List<MatchSuggestion>> tier2FuzzyLookup(Set<String> names) {
        Map<String, List<MatchSuggestion>> result = new Map<String, List<MatchSuggestion>>();
        if (names.isEmpty()) return result;

        // SOSL across Account Name field scoped to Advertiser record type
        // Build a single SOSL query combining all names
        List<List<SObject>> searchResults = new List<List<SObject>>();
        for (String rawName : names) {
            String normalizedInput = normalizeName(rawName);
            if (String.isBlank(normalizedInput)) continue;

            String soslTerm = String.escapeSingleQuotes(normalizedInput) + '*';
            List<List<SObject>> batch = Search.query(
                'FIND \'' + soslTerm + '\' IN NAME FIELDS '
                + 'RETURNING Account(Id, Name, MDM_External_Id__c '
                + 'WHERE RecordType.DeveloperName = \'' + ADVERTISER_RT_NAME + '\') LIMIT 20'
            );

            List<Account> candidates = (List<Account>) batch[0];

            // Score each candidate
            List<MatchSuggestion> ranked = new List<MatchSuggestion>();
            for (Account cand : candidates) {
                Integer score = similarityScore(normalizedInput, normalizeName(cand.Name));
                MatchSuggestion s = new MatchSuggestion();
                s.accountId   = cand.Id;
                s.accountName = cand.Name;
                s.score       = score;
                s.method      = 'FUZZY_NAME';
                ranked.add(s);
            }
            ranked.sort(new SuggestionComparator());

            // Keep top MAX_SUGGESTIONS
            List<MatchSuggestion> top = new List<MatchSuggestion>();
            for (Integer i = 0; i < Math.min(ranked.size(), MAX_SUGGESTIONS); i++) {
                top.add(ranked[i]);
            }
            result.put(rawName, top);
        }
        return result;
    }

    // ── String helpers ────────────────────────────────────────────────────────

    /** Strip punctuation, common suffixes, lower-case for comparison. */
    @TestVisible
    static String normalizeName(String s) {
        if (String.isBlank(s)) return '';
        String n = s.toLowerCase().trim();
        // Remove common legal suffixes
        n = n.replaceAll('\\b(inc|llc|corp|ltd|co|dba|the|a|an)\\b', '');
        // Remove non-alphanumeric
        n = n.replaceAll('[^a-z0-9]', ' ');
        // Collapse whitespace
        n = n.trim().replaceAll('\\s+', ' ');
        return n;
    }

    /**
     * Normalized Levenshtein similarity: 100 = identical, 0 = completely different.
     * Capped at strings of length ≤ 200 for governor limit safety.
     */
    @TestVisible
    static Integer similarityScore(String a, String b) {
        if (String.isBlank(a) && String.isBlank(b)) return 100;
        if (String.isBlank(a) || String.isBlank(b)) return 0;
        a = a.left(200);
        b = b.left(200);
        if (a == b) return 100;
        Integer dist = levenshtein(a, b);
        Integer maxLen = Math.max(a.length(), b.length());
        return maxLen == 0 ? 100 : 100 - ((dist * 100) / maxLen);
    }

    private static Integer levenshtein(String s, String t) {
        Integer m = s.length();
        Integer n = t.length();
        List<Integer> prev = new List<Integer>();
        List<Integer> curr = new List<Integer>();
        for (Integer j = 0; j <= n; j++) prev.add(j);
        for (Integer i = 1; i <= m; i++) {
            curr = new List<Integer>();
            curr.add(i);
            for (Integer j = 1; j <= n; j++) {
                Integer cost = s.substring(i - 1, i) == t.substring(j - 1, j) ? 0 : 1;
                curr.add(Math.min(
                    Math.min(curr[j - 1] + 1, prev[j] + 1),
                    prev[j - 1] + cost
                ));
            }
            prev = curr;
        }
        return prev[n];
    }

    // ── Sort comparator (descending score) ───────────────────────────────────

    private class SuggestionComparator implements Comparator<MatchSuggestion> {
        public Integer compare(MatchSuggestion a, MatchSuggestion b) {
            return b.score - a.score; // descending
        }
    }
}
