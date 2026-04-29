/**
 * Five-tier AE/salesperson matcher with self-healing alias writes.
 *
 * Tier 1 — Exact AE Code:      User.AE_Code__c = rawCode (case-insensitive)
 * Tier 2 — Alias Table:        AE_Code_Alias__c.Name = rawCode (previous self-heal)
 * Tier 3 — Normalized Code:    strip leading zeros + non-alphanumeric, lowercase
 * Tier 4 — User.Alias match:   standard Salesforce User.Alias field (up to 8 chars)
 * Tier 5 — Unmatched:          returns null userId; row flagged for manual queue
 *
 * Self-healing: whenever a Tier 2-4 match succeeds, a new AE_Code_Alias__c is
 * inserted for the raw code, so the next occurrence resolves at Tier 1.
 *
 * Usage (bulk):
 *   Map<String,SalespersonMatcher.AEMatchResult> results =
 *       SalespersonMatcher.matchBulk(rawCodes, sourceSystemCode);
 */
public with sharing class SalespersonMatcher {

    // ── Public types ──────────────────────────────────────────────────────────

    public class AEMatchResult {
        @AuraEnabled public Id      userId { get; set; }
        @AuraEnabled public Integer tier   { get; set; }
        @AuraEnabled public String  method { get; set; }
    }

    // ── Main bulk entry point ─────────────────────────────────────────────────

    /**
     * Returns a map of rawCode → AEMatchResult for every code in the input set.
     * Also queues up self-heal alias writes for Tier 2-4 matches.
     */
    public static Map<String, AEMatchResult> matchBulk(Set<String> rawCodes, String sourceSystemCode) {
        Map<String, AEMatchResult> results = new Map<String, AEMatchResult>();
        if (rawCodes.isEmpty()) return results;

        // Normalise all raw codes once
        Map<String, String> rawToNorm = new Map<String, String>();
        for (String raw : rawCodes) {
            rawToNorm.put(raw, normalizeCode(raw));
        }

        // Tier 1: User.AE_Code__c exact (case-insensitive via lowercase set)
        Set<String> lowerCodes = new Set<String>();
        for (String raw : rawCodes) lowerCodes.add(raw.toLowerCase());

        Map<String, Id> t1Map = new Map<String, Id>();
        for (User u : [
            SELECT Id, AE_Code__c
            FROM   User
            WHERE  AE_Code__c != null
              AND  IsActive = true
        ]) {
            t1Map.put(u.AE_Code__c.toLowerCase(), u.Id);
        }

        // Tier 2: AE_Code_Alias__c lookup
        Map<String, AE_Code_Alias__c> aliasMap = new Map<String, AE_Code_Alias__c>();
        for (AE_Code_Alias__c alias : [
            SELECT Name, User__c
            FROM   AE_Code_Alias__c
            WHERE  Name IN :lowerCodes
        ]) {
            aliasMap.put(alias.Name.toLowerCase(), alias);
        }

        // Tier 4: User.Alias (standard field, up to 8 chars)
        Map<String, Id> aliasFieldMap = new Map<String, Id>();
        for (User u : [
            SELECT Id, Alias
            FROM   User
            WHERE  Alias != null
              AND  IsActive = true
        ]) {
            aliasFieldMap.put(u.Alias.toLowerCase(), u.Id);
        }

        // Collect aliases to self-heal (write after matching)
        List<AE_Code_Alias__c> aliasesToInsert = new List<AE_Code_Alias__c>();

        for (String rawCode : rawCodes) {
            AEMatchResult r = new AEMatchResult();
            String lower = rawCode.toLowerCase();
            String norm  = rawToNorm.get(rawCode);

            if (t1Map.containsKey(lower)) {
                r.userId = t1Map.get(lower);
                r.tier   = 1;
                r.method = 'AE_CODE_EXACT';

            } else if (aliasMap.containsKey(lower)) {
                r.userId = aliasMap.get(lower).User__c;
                r.tier   = 2;
                r.method = 'ALIAS_TABLE';
                // no new alias needed — it already exists

            } else if (String.isNotBlank(norm) && t1Map.containsKey(norm)) {
                r.userId = t1Map.get(norm);
                r.tier   = 3;
                r.method = 'NORMALIZED_CODE';
                aliasesToInsert.add(buildAlias(rawCode, r.userId, sourceSystemCode, norm, 3));

            } else if (String.isNotBlank(lower) && aliasFieldMap.containsKey(lower.left(8))) {
                r.userId = aliasFieldMap.get(lower.left(8));
                r.tier   = 4;
                r.method = 'USER_ALIAS';
                aliasesToInsert.add(buildAlias(rawCode, r.userId, sourceSystemCode, norm, 4));

            } else {
                r.tier   = 5;
                r.method = 'UNMATCHED';
            }
            results.put(rawCode, r);
        }

        // Self-healing writes — allow partial success (allOrNone=false)
        if (!aliasesToInsert.isEmpty()) {
            Database.insert(aliasesToInsert, false);
        }

        return results;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Strip leading zeros, non-alphanumeric chars, lowercase for comparison. */
    @TestVisible
    static String normalizeCode(String raw) {
        if (String.isBlank(raw)) return '';
        String n = raw.toLowerCase().replaceAll('[^a-z0-9]', '').replaceFirst('^0+', '');
        return n;
    }

    private static AE_Code_Alias__c buildAlias(
        String rawCode, Id userId, String sourceSystemCode, String normalizedCode, Integer tier
    ) {
        AE_Code_Alias__c a = new AE_Code_Alias__c();
        a.Name                = rawCode.left(80);
        a.User__c             = userId;
        a.Source_System_Code__c = sourceSystemCode;
        a.Normalized_Code__c  = normalizedCode != null ? normalizedCode.left(50) : null;
        a.Match_Tier__c       = tier;
        a.Last_Used__c        = Datetime.now();
        return a;
    }
}
