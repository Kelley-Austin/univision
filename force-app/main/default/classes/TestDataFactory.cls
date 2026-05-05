/**
 * =============================================================================
 *  TestDataFactory — Centralized test data construction
 * =============================================================================
 *
 *  Why this class exists
 *  ---------------------
 *  Every Apex test that touches an sObject ends up writing the same
 *  boilerplate: look up record-type IDs, populate required fields, generate
 *  unique external keys, insert. When that boilerplate is duplicated across
 *  fifty test classes:
 *    * Fields drift — one test sets Revenue_Type__c and another forgets it.
 *    * Adding a new required field requires hunting through dozens of files.
 *    * "Test setup" creeps into 80-line @TestSetup blocks that bury the
 *      actual assertion under a wall of arrange-step noise.
 *
 *  This factory provides one-line construction for every common project
 *  sObject so test methods can stay focused on Arrange / Act / Assert.
 *
 *  Method conventions
 *  ------------------
 *      buildX(...)   — returns an UNSAVED sObject with sensible defaults.
 *                      Use this when you need to mutate the row before insert
 *                      (e.g. setting a field that drives the test) or when
 *                      you want to bulk-insert a list outside the factory.
 *
 *      createX(...)  — builds, inserts, returns the saved sObject.
 *                      Use this when the row's only role is "exist so the
 *                      thing under test has a parent to lookup."
 *
 *  Defaults are deliberately minimal — exactly the required fields plus any
 *  field tests usually want stamped (Name, Period_Year__c, etc.). If a test
 *  needs to vary a field, the build/create signature accepts an override or
 *  the test mutates the returned row before insert.
 *
 *  Uniqueness
 *  ----------
 *  The static counter (`uniq`) appends a deterministic suffix to names and
 *  external keys so multiple objects created in one test don't collide on
 *  unique constraints. Counter is per-transaction (statics reset between
 *  test methods) so you don't need to reset it manually.
 *
 *  When NOT to use this factory
 *  ----------------------------
 *  Tests that intentionally exercise edge cases (missing required fields,
 *  malformed external keys, duplicate composite keys) should construct rows
 *  manually. The factory's defaults are the *valid* path; bypassing them is
 *  the point of those tests.
 *
 *  Adding a new method
 *  -------------------
 *  When you reach for "new X__c(...)" in a test for the third time, add it
 *  here. Place the method in the matching object section, give it the
 *  smallest plausible parameter list, and return the unsaved row from the
 *  buildX variant.
 * =============================================================================
 */
@IsTest
public class TestDataFactory {

    // =========================================================================
    //  Uniqueness counter
    // =========================================================================
    // Per-transaction monotonically-increasing integer used to make Names,
    // External_Key__c, etc. distinct across multiple build/create calls in
    // the same test method. Statics reset between test methods, so callers
    // never have to reset this.
    private static Integer uniq = 0;

    /**
     * Returns "1", "2", "3", … each call. Use as a suffix to force unique
     * names / keys when the factory is invoked multiple times in one test.
     */
    @TestVisible
    private static String nextSuffix() {
        uniq++;
        return String.valueOf(uniq);
    }

    // =========================================================================
    //  Record type helper
    // =========================================================================

    /**
     * Look up a record type Id by sObject + developer name. Cached per
     * (objectName, devName) for the life of the transaction.
     *
     * Throws TestDataFactoryException if the record type doesn't exist —
     * better to fail loudly in test setup than to silently insert with no
     * record type and watch downstream assertions fail mysteriously.
     */
    @TestVisible
    private static Map<String, Id> recordTypeCache = new Map<String, Id>();

    public static Id recordTypeId(SObjectType type, String developerName) {
        String objectName = type.getDescribe().getName();
        String key = objectName + ':' + developerName;
        if (recordTypeCache.containsKey(key)) return recordTypeCache.get(key);

        Map<String, Schema.RecordTypeInfo> infos =
            type.getDescribe().getRecordTypeInfosByDeveloperName();
        if (!infos.containsKey(developerName)) {
            throw new TestDataFactoryException(
                'No record type "' + developerName + '" on ' + objectName +
                '. Check the org has the record type deployed before this test runs.'
            );
        }
        Id rtId = infos.get(developerName).getRecordTypeId();
        recordTypeCache.put(key, rtId);
        return rtId;
    }

    /**
     * Custom exception type so callers / matchers can distinguish factory
     * failures from genuine assertion failures.
     */
    public class TestDataFactoryException extends Exception {}

    // =========================================================================
    //  Account
    // =========================================================================

    /**
     * Build an unsaved Advertiser-record-type Account. If the org doesn't
     * have an "Advertiser" record type, falls back to an Account with no
     * record type (most dev orgs don't enforce this — production does).
     */
    public static Account buildAdvertiser(String name) {
        Account a = new Account(Name = name);
        try {
            a.RecordTypeId = recordTypeId(Account.SObjectType, 'Advertiser');
        } catch (TestDataFactoryException ignored) {
            // Org without the RT — leave RecordTypeId null. Tests that
            // *require* the RT should call recordTypeId() themselves and
            // fail loudly.
        }
        return a;
    }

    public static Account createAdvertiser(String name) {
        Account a = buildAdvertiser(name);
        insert a;
        return a;
    }

    /**
     * Build an unsaved Agency-record-type Account.
     */
    public static Account buildAgency(String name) {
        Account a = new Account(Name = name);
        try {
            a.RecordTypeId = recordTypeId(Account.SObjectType, 'Agency');
        } catch (TestDataFactoryException ignored) { /* see buildAdvertiser */ }
        return a;
    }

    public static Account createAgency(String name) {
        Account a = buildAgency(name);
        insert a;
        return a;
    }

    /**
     * Build an unsaved HoldCo-record-type Account.
     */
    public static Account buildHoldCo(String name) {
        Account a = new Account(Name = name);
        try {
            a.RecordTypeId = recordTypeId(Account.SObjectType, 'HoldCo');
        } catch (TestDataFactoryException ignored) { /* see buildAdvertiser */ }
        return a;
    }

    public static Account createHoldCo(String name) {
        Account a = buildHoldCo(name);
        insert a;
        return a;
    }

    // =========================================================================
    //  Contact
    // =========================================================================

    /**
     * Build a Contact attached to the supplied Account. Email is left blank
     * by default; set it on the returned row if the test needs it.
     */
    public static Contact buildContact(Id accountId, String lastName) {
        return new Contact(
            AccountId = accountId,
            LastName  = lastName
        );
    }

    public static Contact createContact(Id accountId, String lastName) {
        Contact c = buildContact(accountId, lastName);
        insert c;
        return c;
    }

    // =========================================================================
    //  Category + Account_Category
    // =========================================================================

    /**
     * Build a Category__c with the supplied display name.
     */
    public static Category__c buildCategory(String name) {
        return new Category__c(Name = name);
    }

    public static Category__c createCategory(String name) {
        Category__c c = buildCategory(name);
        insert c;
        return c;
    }

    /**
     * Build the junction record linking an Account to a Category.
     * (The original method also set Is_Primary__c, but that field doesn't
     * exist on Account_Category__c in this org. If/when it's added, the
     * isPrimary parameter can be reintroduced.)
     */
    public static Account_Category__c buildAccountCategory(Id accountId, Id categoryId) {
        return new Account_Category__c(
            Account__c  = accountId,
            Category__c = categoryId
        );
    }

    public static Account_Category__c createAccountCategory(Id accountId, Id categoryId) {
        Account_Category__c ac = buildAccountCategory(accountId, categoryId);
        insert ac;
        return ac;
    }

    // =========================================================================
    //  Period_Close__c
    // =========================================================================

    /**
     * Build an OPEN period close with the supplied year/month. Composite_Key__c
     * matches the convention used by ActualRevenueTriggerHandler.flagLateActuals
     * ("YYYY|M" — no zero-pad on month).
     */
    public static Period_Close__c buildOpenPeriod(Integer year, Integer month) {
        return new Period_Close__c(
            Period_Year__c   = year,
            Period_Month__c  = month,
            Status__c        = 'Open',
            Composite_Key__c = year + '|' + month
        );
    }

    public static Period_Close__c createOpenPeriod(Integer year, Integer month) {
        Period_Close__c pc = buildOpenPeriod(year, month);
        insert pc;
        return pc;
    }

    /**
     * Build a CLOSED period with the supplied close date. Use a closeDate in
     * the PAST when you want to assert that subsequent inserts are flagged
     * Is_Late__c = true. Use a future date for not-late.
     */
    public static Period_Close__c buildClosedPeriod(Integer year, Integer month, Date closeDate) {
        return new Period_Close__c(
            Period_Year__c   = year,
            Period_Month__c  = month,
            Status__c        = 'Closed',
            Close_Date__c    = closeDate,
            Composite_Key__c = year + '|' + month
        );
    }

    public static Period_Close__c createClosedPeriod(Integer year, Integer month, Date closeDate) {
        Period_Close__c pc = buildClosedPeriod(year, month, closeDate);
        insert pc;
        return pc;
    }

    // =========================================================================
    //  Projection__c
    // =========================================================================

    /**
     * Build a Projection__c keyed on the supplied dimensions. Composite_Key__c
     * is left blank — the trigger's beforeInsert phase will stamp it via
     * ProjectionTriggerHandler.buildCompositeKey on save. If you're inserting
     * outside the trigger's path, call buildCompositeKey() yourself.
     *
     * Stage__c defaults to 'Working' (Stage 0 of the forecast pipeline).
     * Override on the returned row when testing stage transitions.
     */
    public static Projection__c buildProjection(
        Id accountId, Id categoryId, String revenueType, Integer year, Integer month, Decimal amount
    ) {
        return new Projection__c(
            Account__c       = accountId,
            Category__c      = categoryId,
            Revenue_Type__c  = revenueType,
            Period_Year__c   = year,
            Period_Month__c  = month,
            Amount__c        = amount,
            Stage__c         = 'Working'
        );
    }

    public static Projection__c createProjection(
        Id accountId, Id categoryId, String revenueType, Integer year, Integer month, Decimal amount
    ) {
        Projection__c p = buildProjection(accountId, categoryId, revenueType, year, month, amount);
        insert p;
        return p;
    }

    // =========================================================================
    //  Actual_Revenue__c
    // =========================================================================

    /**
     * Build an Actual_Revenue__c with a unique External_Key__c. Use this in
     * ingest-pipeline tests where you need a row to dedupe-key against.
     *
     * Required: account, period — these drive the rollup composite key.
     * Optional: categoryId may be null for revenue not tied to a category;
     * the trigger handles the null path.
     */
    public static Actual_Revenue__c buildActual(
        Id accountId, Id categoryId, String revenueType,
        Integer year, Integer month, Decimal amount
    ) {
        return new Actual_Revenue__c(
            Account__c        = accountId,
            Category__c       = categoryId,
            Revenue_Type__c   = revenueType,
            Period_Year__c    = year,
            Period_Month__c   = month,
            Revenue_Amount__c = amount,
            External_Key__c   = 'TEST-EXT-' + nextSuffix()
        );
    }

    public static Actual_Revenue__c createActual(
        Id accountId, Id categoryId, String revenueType,
        Integer year, Integer month, Decimal amount
    ) {
        Actual_Revenue__c a = buildActual(accountId, categoryId, revenueType, year, month, amount);
        insert a;
        return a;
    }

    // =========================================================================
    //  Source_System__c
    // =========================================================================

    /**
     * Build a Source_System__c with the supplied code (the unique discriminator
     * used by TransformerRegistry to route inbound files).
     */
    public static Source_System__c buildSourceSystem(String code, String name) {
        return new Source_System__c(
            Name    = name,
            Code__c = code
        );
    }

    public static Source_System__c createSourceSystem(String code, String name) {
        Source_System__c s = buildSourceSystem(code, name);
        insert s;
        return s;
    }

    // =========================================================================
    //  Inbound_Staging__c
    // =========================================================================

    /**
     * Build an Inbound_Staging__c row in 'Pending' status. Real ingest paths
     * fill many more fields (Source_Advertiser_Id, AE_Code_Raw, etc.) — keep
     * this method's signature minimal and let tests stamp the rest as needed.
     */
    public static Inbound_Staging__c buildStaging(
        Id sourceSystemId, Integer year, Integer month, Decimal amount
    ) {
        return new Inbound_Staging__c(
            Source_System__c    = sourceSystemId,
            Period_Year__c      = year,
            Period_Month__c     = month,
            Revenue_Amount__c   = amount,
            Status__c           = 'Pending',
            External_Key__c     = 'TEST-STG-' + nextSuffix()
        );
    }

    public static Inbound_Staging__c createStaging(
        Id sourceSystemId, Integer year, Integer month, Decimal amount
    ) {
        Inbound_Staging__c s = buildStaging(sourceSystemId, year, month, amount);
        insert s;
        return s;
    }

    // =========================================================================
    //  Budget__c
    // =========================================================================

    /**
     * Build a Budget__c with the supplied dimension/amount. Most fields on
     * Budget__c are 12 monthly amounts plus a formula total — tests targeting
     * those usually want to set them explicitly.
     */
    public static Budget__c buildBudget(Id accountId, Integer year) {
        return new Budget__c(
            Account__c     = accountId,
            Period_Year__c = year
        );
    }

    public static Budget__c createBudget(Id accountId, Integer year) {
        Budget__c b = buildBudget(accountId, year);
        insert b;
        return b;
    }

    // =========================================================================
    //  Minimum-viable-world helper
    // =========================================================================

    /**
     * Seed the smallest set of records most tests need: one Advertiser, one
     * Category, one Open period, one Closed period (with a past close date).
     * Returns a wrapper struct so tests can grab the IDs they care about
     * without re-querying.
     *
     * If your test needs more / different rows, use the per-object factories
     * above. seedWorld() is a convenience for the "I just want SOMETHING in
     * the org" case — typically the @TestSetup of a focused test class.
     */
    public class SeededWorld {
        public Account     advertiser;
        public Category__c category;
        public Period_Close__c openPeriod;
        public Period_Close__c closedPeriod;
    }

    public static SeededWorld seedWorld() {
        SeededWorld w = new SeededWorld();
        w.advertiser   = createAdvertiser('Seed Advertiser ' + nextSuffix());
        w.category     = createCategory('Seed Category ' + nextSuffix());
        // Open: this month next year — far enough out that no test mistakes
        // it for a closed period.
        Date today = Date.today();
        w.openPeriod   = createOpenPeriod(today.year() + 1, today.month());
        // Closed: Jan of the previous year, closed Jan 31 of that year. Close
        // date is in the past relative to any reasonable test runtime.
        w.closedPeriod = createClosedPeriod(today.year() - 1, 1, Date.newInstance(today.year() - 1, 1, 31));
        return w;
    }
}
