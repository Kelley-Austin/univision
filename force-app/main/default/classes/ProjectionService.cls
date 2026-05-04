public with sharing class ProjectionService {

    // ── Inner types ────────────────────────────────────────────────────────────

    public class ProjectionRow {
        @AuraEnabled public Integer month      { get; set; }
        @AuraEnabled public String  monthLabel { get; set; }
        @AuraEnabled public Decimal amount     { get; set; }
        @AuraEnabled public String  stage      { get; set; }
        @AuraEnabled public String  projId     { get; set; }
        @AuraEnabled public String  compositeKey { get; set; }
    }

    public class ProjectionInput {
        @AuraEnabled public String  accountId    { get; set; }
        @AuraEnabled public String  categoryId   { get; set; }
        @AuraEnabled public String  revenueType  { get; set; }
        @AuraEnabled public Integer periodYear   { get; set; }
        @AuraEnabled public Integer periodMonth  { get; set; }
        @AuraEnabled public Decimal amount       { get; set; }
        @AuraEnabled public String  stage        { get; set; }
    }

    public class GridRow {
        @AuraEnabled public String   categoryId         { get; set; }
        @AuraEnabled public String   categoryName       { get; set; }
        @AuraEnabled public String   revenueType        { get; set; }
        @AuraEnabled public List<Decimal> budgetAmounts     { get; set; }
        @AuraEnabled public List<Decimal> projectionAmounts { get; set; }
        @AuraEnabled public List<Decimal> actualAmounts     { get; set; }
        @AuraEnabled public List<Decimal> varianceAmounts   { get; set; }
        @AuraEnabled public Decimal  totalBudget        { get; set; }
        @AuraEnabled public Decimal  totalProjection    { get; set; }
        @AuraEnabled public Decimal  totalActual        { get; set; }
        @AuraEnabled public Decimal  totalVariance      { get; set; }
    }

    public class UpsertResult {
        @AuraEnabled public Boolean success      { get; set; }
        @AuraEnabled public String  message      { get; set; }
        @AuraEnabled public Integer savedCount   { get; set; }
        @AuraEnabled public Integer errorCount   { get; set; }
    }

    // ── Grid data for aeProjectionGrid ────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ProjectionRow> getProjections(
        Id accountId, Id categoryId, String revenueType, Integer periodYear
    ) {
        Map<Integer, ProjectionRow> byMonth = new Map<Integer, ProjectionRow>();
        for (Integer m = 1; m <= 12; m++) {
            ProjectionRow row = new ProjectionRow();
            row.month      = m;
            row.monthLabel = monthLabel(m);
            row.amount     = 0;
            row.stage      = 'Working';
            byMonth.put(m, row);
        }

        for (Projection__c proj : [
            SELECT Id, Period_Month__c, Amount__c, Stage__c, Composite_Key__c
            FROM   Projection__c
            WHERE  Account__c    = :accountId
              AND  Category__c   = :categoryId
              AND  Revenue_Type__c = :revenueType
              AND  Period_Year__c  = :periodYear
            LIMIT 200
        ]) {
            Integer m = proj.Period_Month__c != null ? proj.Period_Month__c.intValue() : 0;
            if (byMonth.containsKey(m)) {
                ProjectionRow row = byMonth.get(m);
                row.amount       = proj.Amount__c != null ? proj.Amount__c : 0;
                row.stage        = proj.Stage__c;
                row.projId       = proj.Id;
                row.compositeKey = proj.Composite_Key__c;
            }
        }

        List<ProjectionRow> result = new List<ProjectionRow>();
        for (Integer m = 1; m <= 12; m++) {
            result.add(byMonth.get(m));
        }
        return result;
    }

    // ── Budget grid data for accountBudgetGrid ────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<GridRow> getBudgetGridData(
        Id accountId, Id categoryId, String revenueType, Integer periodYear
    ) {
        // Build dimension filter conditions dynamically
        String catFilter  = categoryId  != null ? 'AND Category__c = :categoryId '   : '';
        String typeFilter = String.isNotBlank(revenueType) ? 'AND Revenue_Type__c = :revenueType ' : '';

        // Query Budget__c
        List<Budget__c> budgets = Database.query(
            'SELECT Id, Category__c, Category__r.Name, Revenue_Type__c, ' +
            '  Jan_Budget__c, Feb_Budget__c, Mar_Budget__c, Apr_Budget__c, ' +
            '  May_Budget__c, Jun_Budget__c, Jul_Budget__c, Aug_Budget__c, ' +
            '  Sep_Budget__c, Oct_Budget__c, Nov_Budget__c, Dec_Budget__c ' +
            'FROM Budget__c ' +
            'WHERE Account__c = :accountId ' +
            '  AND Period_Year__c = :periodYear ' +
            catFilter + typeFilter +
            'LIMIT 200'
        );

        // Query Projection__c — fetch individual rows, aggregate in Apex to avoid type-cast issues
        List<SObject> projections = Database.query(
            'SELECT Category__c, Revenue_Type__c, Period_Month__c, Amount__c ' +
            'FROM Projection__c ' +
            'WHERE Account__c = :accountId ' +
            '  AND Period_Year__c = :periodYear ' +
            catFilter + typeFilter +
            'LIMIT 500'
        );

        // Query Actual_Revenue__c
        List<SObject> actuals = Database.query(
            'SELECT Category__c, Revenue_Type__c, Period_Month__c, Amount__c ' +
            'FROM Actual_Revenue__c ' +
            'WHERE Account__c = :accountId ' +
            '  AND Period_Year__c = :periodYear ' +
            catFilter + typeFilter +
            'LIMIT 500'
        );

        // Key: categoryId + '|' + revenueType
        Map<String, List<Decimal>> projMap   = buildMonthlyMap(projections);
        Map<String, List<Decimal>> actualMap = buildMonthlyMap(actuals);

        List<GridRow> rows = new List<GridRow>();
        for (Budget__c bud : budgets) {
            String key = String.valueOf(bud.Category__c) + '|' + bud.Revenue_Type__c;
            List<Decimal> budAmts  = budgetMonthList(bud);
            List<Decimal> projAmts = projMap.containsKey(key) ? projMap.get(key) : emptyMonths();
            List<Decimal> actAmts  = actualMap.containsKey(key) ? actualMap.get(key) : emptyMonths();

            GridRow row = new GridRow();
            row.categoryId         = bud.Category__c;
            row.categoryName       = bud.Category__r.Name;
            row.revenueType        = bud.Revenue_Type__c;
            row.budgetAmounts      = budAmts;
            row.projectionAmounts  = projAmts;
            row.actualAmounts      = actAmts;
            row.varianceAmounts    = computeVariance(actAmts, budAmts);
            row.totalBudget        = sumList(budAmts);
            row.totalProjection    = sumList(projAmts);
            row.totalActual        = sumList(actAmts);
            row.totalVariance      = row.totalActual - row.totalBudget;
            rows.add(row);
        }
        return rows;
    }

    // ── Upsert projections from grid ──────────────────────────────────────────

    @AuraEnabled
    public static UpsertResult upsertProjections(String projectionsJson) {
        UpsertResult result = new UpsertResult();
        result.savedCount = 0;
        result.errorCount = 0;

        List<ProjectionInput> inputs;
        try {
            inputs = (List<ProjectionInput>) JSON.deserialize(projectionsJson, List<ProjectionInput>.class);
        } catch (Exception ex) {
            result.success = false;
            result.message = 'Invalid input: ' + ex.getMessage();
            return result;
        }

        if (inputs == null || inputs.isEmpty()) {
            result.success = true;
            result.message = 'Nothing to save.';
            return result;
        }

        // Check lock for the first record's context (all inputs share same acct/cat/type/year)
        ProjectionInput first = inputs[0];
        BudgetLockService.LockResult lockResult = BudgetLockService.checkLock(
            first.accountId, first.categoryId, first.revenueType, first.periodYear
        );
        if (lockResult.isLocked) {
            result.success = false;
            result.message = lockResult.lockMessage;
            return result;
        }

        List<Projection__c> records = new List<Projection__c>();
        for (ProjectionInput inp : inputs) {
            Projection__c proj = new Projection__c(
                Account__c      = inp.accountId,
                Category__c     = inp.categoryId,
                Revenue_Type__c = inp.revenueType,
                Period_Year__c  = inp.periodYear,
                Period_Month__c = inp.periodMonth,
                Amount__c       = inp.amount != null ? inp.amount : 0,
                Stage__c        = String.isNotBlank(inp.stage) ? inp.stage : 'Working'
            );
            // Set composite key here so upsert matching works before trigger fires
            proj.Composite_Key__c = ProjectionTriggerHandler.buildCompositeKey(proj);
            records.add(proj);
        }

        Database.UpsertResult[] dbResults = Database.upsert(records, Projection__c.Composite_Key__c, false);
        for (Database.UpsertResult dr : dbResults) {
            if (dr.isSuccess()) {
                result.savedCount++;
            } else {
                result.errorCount++;
            }
        }

        result.success = (result.errorCount == 0);
        result.message = result.success
            ? result.savedCount + ' projection(s) saved.'
            : result.savedCount + ' saved, ' + result.errorCount + ' failed.';
        return result;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static String monthLabel(Integer m) {
        String[] labels = new String[]{ 'Jan','Feb','Mar','Apr','May','Jun',
                                        'Jul','Aug','Sep','Oct','Nov','Dec' };
        return labels[m - 1];
    }

    private static List<Decimal> emptyMonths() {
        List<Decimal> m = new List<Decimal>();
        for (Integer i = 0; i < 12; i++) { m.add(0); }
        return m;
    }

    private static List<Decimal> budgetMonthList(Budget__c b) {
        return new List<Decimal>{
            b.Jan_Budget__c != null ? b.Jan_Budget__c : 0,
            b.Feb_Budget__c != null ? b.Feb_Budget__c : 0,
            b.Mar_Budget__c != null ? b.Mar_Budget__c : 0,
            b.Apr_Budget__c != null ? b.Apr_Budget__c : 0,
            b.May_Budget__c != null ? b.May_Budget__c : 0,
            b.Jun_Budget__c != null ? b.Jun_Budget__c : 0,
            b.Jul_Budget__c != null ? b.Jul_Budget__c : 0,
            b.Aug_Budget__c != null ? b.Aug_Budget__c : 0,
            b.Sep_Budget__c != null ? b.Sep_Budget__c : 0,
            b.Oct_Budget__c != null ? b.Oct_Budget__c : 0,
            b.Nov_Budget__c != null ? b.Nov_Budget__c : 0,
            b.Dec_Budget__c != null ? b.Dec_Budget__c : 0
        };
    }

    private static Map<String, List<Decimal>> buildMonthlyMap(List<SObject> records) {
        Map<String, List<Decimal>> result = new Map<String, List<Decimal>>();
        for (SObject rec : records) {
            Id      catId = (Id)      rec.get('Category__c');
            String  rType = (String)  rec.get('Revenue_Type__c');
            Decimal mDec  = (Decimal) rec.get('Period_Month__c');
            Decimal amt   = (Decimal) rec.get('Amount__c');

            if (catId == null || rType == null || mDec == null) { continue; }
            Integer month = mDec.intValue();
            String  key   = String.valueOf(catId) + '|' + rType;

            if (!result.containsKey(key)) {
                result.put(key, emptyMonths());
            }
            if (month >= 1 && month <= 12) {
                Decimal existing = result.get(key).get(month - 1);
                result.get(key).set(month - 1, (existing != null ? existing : 0) + (amt != null ? amt : 0));
            }
        }
        return result;
    }

    private static List<Decimal> computeVariance(List<Decimal> actuals, List<Decimal> budgets) {
        List<Decimal> variance = new List<Decimal>();
        for (Integer i = 0; i < 12; i++) {
            variance.add((actuals.get(i) != null ? actuals.get(i) : 0)
                       - (budgets.get(i) != null ? budgets.get(i) : 0));
        }
        return variance;
    }

    private static Decimal sumList(List<Decimal> vals) {
        Decimal total = 0;
        for (Decimal v : vals) { total += (v != null ? v : 0); }
        return total;
    }
}
