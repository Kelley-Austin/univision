/**
 * Daily batch that materializes one Pacing_Snapshot__c per Projection grain per day.
 * Upserts on Composite_Key__c (AccountId|CategoryId|RevType|Year|Month|SnapshotDate).
 *
 * Schedule via PacingSnapshotScheduler or run ad-hoc:
 *   Database.executeBatch(new PacingSnapshotBatch(), 200);
 */
public with sharing class PacingSnapshotBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private final Date    snapshotDate;
    private       Integer upserted = 0;
    private       Integer errors   = 0;

    public PacingSnapshotBatch() {
        this(Date.today());
    }

    public PacingSnapshotBatch(Date snapshotDate) {
        this.snapshotDate = snapshotDate;
    }

    // ── Batchable interface ───────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Integer fromYear = snapshotDate.year();
        return Database.getQueryLocator([
            SELECT Id, Account__c, Category__c, Revenue_Type__c,
                   Period_Year__c, Period_Month__c,
                   Amount__c, Actual_Amount__c, Stage__c
            FROM   Projection__c
            WHERE  Period_Year__c >= :fromYear
            ORDER BY Account__c, Period_Year__c, Period_Month__c
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Projection__c> scope) {
        Set<Id>      acctIds  = new Set<Id>();
        Set<Id>      catIds   = new Set<Id>();
        Set<Integer> years    = new Set<Integer>();
        Set<Integer> months   = new Set<Integer>();

        for (Projection__c p : scope) {
            if (p.Account__c  != null) { acctIds.add(p.Account__c); }
            if (p.Category__c != null) { catIds.add(p.Category__c); }
            if (p.Period_Year__c  != null) { years.add(p.Period_Year__c.intValue()); }
            if (p.Period_Month__c != null) { months.add(p.Period_Month__c.intValue()); }
        }

        Set<Integer> lyYears = new Set<Integer>();
        for (Integer yr : years) { lyYears.add(yr - 1); }

        // ── Budget lookup: account|category|revType|year → month → amount ──────
        // Key: acctId|catId|revType|year|month
        Map<String, Decimal> budgetMap = buildBudgetMap(acctIds, catIds, years, months);

        // ── Last-year actual lookup ───────────────────────────────────────────
        // Key: acctId|catId|revType|(year-1)|month
        Map<String, Decimal> lyMap = buildLastYearMap(acctIds, catIds, lyYears, months);

        // ── Build snapshots ───────────────────────────────────────────────────
        List<Pacing_Snapshot__c> snapshots = new List<Pacing_Snapshot__c>();
        for (Projection__c proj : scope) {
            if (proj.Account__c == null || proj.Category__c == null) { continue; }

            Integer yr    = proj.Period_Year__c  != null ? proj.Period_Year__c.intValue()  : 0;
            Integer mo    = proj.Period_Month__c != null ? proj.Period_Month__c.intValue() : 0;
            String  acct  = String.valueOf(proj.Account__c);
            String  cat   = String.valueOf(proj.Category__c);
            String  rt    = proj.Revenue_Type__c != null ? proj.Revenue_Type__c : '';
            String  stage = proj.Stage__c != null ? proj.Stage__c : 'Working';
            Decimal amt   = proj.Amount__c        != null ? proj.Amount__c        : 0;
            Decimal actAmt = proj.Actual_Amount__c != null ? proj.Actual_Amount__c : 0;

            // Weighted forecast: Won=1.0, Committed=0.6, Pitched=0.3, Working=0.1
            Decimal booked   = stage == 'Won'                             ? amt : 0;
            Decimal pending  = (stage == 'Committed' || stage == 'Pitched') ? amt : 0;
            Decimal forecast = (stage == 'Won'       ? amt * 1.0 : 0)
                             + (stage == 'Committed' ? amt * 0.6 : 0)
                             + (stage == 'Pitched'   ? amt * 0.3 : 0)
                             + (stage == 'Working'   ? amt * 0.1 : 0);

            String dataKey = acct + '|' + cat + '|' + rt + '|' + yr + '|' + mo;
            String lyKey   = acct + '|' + cat + '|' + rt + '|' + (yr - 1) + '|' + mo;

            Pacing_Snapshot__c snap = new Pacing_Snapshot__c(
                Account__c          = proj.Account__c,
                Category__c         = proj.Category__c,
                Revenue_Type__c     = proj.Revenue_Type__c,
                Period_Year__c      = yr,
                Period_Month__c     = mo,
                Snapshot_Date__c    = snapshotDate,
                Booked_Amount__c    = booked,
                Pending_Amount__c   = pending,
                Forecast_Amount__c  = forecast,
                Budget_Amount__c    = budgetMap.containsKey(dataKey) ? budgetMap.get(dataKey) : 0,
                Last_Year_Amount__c = lyMap.containsKey(lyKey)       ? lyMap.get(lyKey)       : 0,
                Actual_Amount__c    = actAmt
            );
            snap.Composite_Key__c = acct + '|' + cat + '|' + rt + '|' + yr + '|' + mo
                                  + '|' + String.valueOf(snapshotDate);
            snapshots.add(snap);
        }

        if (snapshots.isEmpty()) { return; }
        Database.UpsertResult[] results = Database.upsert(
            snapshots, Pacing_Snapshot__c.Composite_Key__c, false
        );
        for (Database.UpsertResult r : results) {
            if (r.isSuccess()) { upserted++; } else { errors++; }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'PacingSnapshotBatch complete — date: ' + snapshotDate
            + ', upserted: ' + upserted + ', errors: ' + errors);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static Map<String, Decimal> buildBudgetMap(
        Set<Id> acctIds, Set<Id> catIds, Set<Integer> years, Set<Integer> months
    ) {
        Map<String, Decimal> m = new Map<String, Decimal>();
        for (Budget__c bud : [
            SELECT Account__c, Category__c, Revenue_Type__c, Period_Year__c,
                   Jan_Budget__c, Feb_Budget__c, Mar_Budget__c, Apr_Budget__c,
                   May_Budget__c, Jun_Budget__c, Jul_Budget__c, Aug_Budget__c,
                   Sep_Budget__c, Oct_Budget__c, Nov_Budget__c, Dec_Budget__c
            FROM   Budget__c
            WHERE  Account__c    IN :acctIds
              AND  Category__c   IN :catIds
              AND  Period_Year__c IN :years
            LIMIT 2000
        ]) {
            Integer yr   = bud.Period_Year__c.intValue();
            String  acct = String.valueOf(bud.Account__c);
            String  cat  = String.valueOf(bud.Category__c);
            String  rt   = bud.Revenue_Type__c != null ? bud.Revenue_Type__c : '';
            for (Integer mo = 1; mo <= 12; mo++) {
                if (!months.contains(mo)) { continue; }
                String key = acct + '|' + cat + '|' + rt + '|' + yr + '|' + mo;
                m.put(key, monthlyBudgetValue(bud, mo));
            }
        }
        return m;
    }

    private static Map<String, Decimal> buildLastYearMap(
        Set<Id> acctIds, Set<Id> catIds, Set<Integer> lyYears, Set<Integer> months
    ) {
        Map<String, Decimal> m = new Map<String, Decimal>();
        if (lyYears.isEmpty() || months.isEmpty()) { return m; }
        for (AggregateResult ar : [
            SELECT Account__c, Category__c, Revenue_Type__c,
                   Period_Year__c pyr, Period_Month__c pmo,
                   SUM(Amount__c) total
            FROM   Actual_Revenue__c
            WHERE  Account__c    IN :acctIds
              AND  Category__c   IN :catIds
              AND  Period_Year__c  IN :lyYears
              AND  Period_Month__c IN :months
            GROUP BY Account__c, Category__c, Revenue_Type__c, Period_Year__c, Period_Month__c
            LIMIT 2000
        ]) {
            String key = String.valueOf(ar.get('Account__c'))  + '|'
                       + String.valueOf(ar.get('Category__c')) + '|'
                       + (ar.get('Revenue_Type__c') != null ? String.valueOf(ar.get('Revenue_Type__c')) : '') + '|'
                       + String.valueOf(((Decimal) ar.get('pyr')).intValue()) + '|'
                       + String.valueOf(((Decimal) ar.get('pmo')).intValue());
            m.put(key, (Decimal) ar.get('total') != null ? (Decimal) ar.get('total') : 0);
        }
        return m;
    }

    private static Decimal monthlyBudgetValue(Budget__c b, Integer mo) {
        Decimal[] vals = new Decimal[]{
            b.Jan_Budget__c, b.Feb_Budget__c, b.Mar_Budget__c,
            b.Apr_Budget__c, b.May_Budget__c, b.Jun_Budget__c,
            b.Jul_Budget__c, b.Aug_Budget__c, b.Sep_Budget__c,
            b.Oct_Budget__c, b.Nov_Budget__c, b.Dec_Budget__c
        };
        Decimal v = vals[mo - 1];
        return v != null ? v : 0;
    }
}
