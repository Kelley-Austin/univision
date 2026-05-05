/**
 * =============================================================================
 *  TestSettings — Compile-time switches that influence behavior under test
 * =============================================================================
 *
 *  Apex tests run in the same Apex namespace as production code, so any "is
 *  this a test?" branching ends up sprinkled across handler classes as
 *  Test.isRunningTest() checks. That couples production code to test concerns
 *  and makes it hard to selectively enable a behavior for a SINGLE test.
 *
 *  This class centralizes those switches in one place. A handler that would
 *  cause noisy / hard-to-assert side effects under test (enqueueing async
 *  jobs, sending emails, posting feed items, calling out, etc.) checks the
 *  appropriate flag here instead. Tests that DO want to exercise the side
 *  effect flip the flag inside their @IsTest method, run under
 *  Test.startTest() / Test.stopTest() so the framework flushes the async
 *  work, and assert on the resulting state.
 *
 *  Example
 *  -------
 *      @IsTest
 *      static void testRollupFiresAfterInsert() {
 *          TestSettings.enableQueueableInTests = true;
 *          Test.startTest();
 *          insert someActuals;
 *          Test.stopTest();   // Queueable runs here, before assertions
 *          // ... assert Projection_c.Actual_Amount__c was rolled up
 *      }
 *
 *  Conventions
 *  -----------
 *    * Default values must be the SAFEST choice for tests that don't know
 *      about this class — i.e. async / outbound side effects DEFAULT TO OFF.
 *    * Production code MUST always check these flags through this class, not
 *      via direct Test.isRunningTest() peppered through handler bodies.
 *    * Reset is automatic: each test method gets fresh statics, so you do not
 *      need a tearDown — but if you set a flag inside @TestSetup, be aware
 *      every test method in the class will inherit that state.
 * =============================================================================
 */
@SuppressWarnings('PMD.ClassNamingConventions')
public class TestSettings {

    /**
     * When false (default), trigger-side enqueue calls (e.g. ProjectionRollupQueueable
     * fired from afterInsert on Actual_Revenue__c) are skipped under test
     * context. Set to true in a specific @IsTest method to validate async
     * rollup behavior end-to-end.
     */
    public static Boolean enableQueueableInTests = false;

    /**
     * When false (default), tests do not send emails. If a future feature
     * needs to assert email content, flip this on for that test only.
     */
    public static Boolean enableEmailInTests = false;

    /**
     * When false (default), tests do not perform external HTTP callouts even
     * if a mocked response is registered. Forces tests to opt in explicitly
     * via this flag AND Test.setMock(). Belt-and-braces.
     */
    public static Boolean enableCalloutsInTests = false;

    // No instances; statics only.
    private TestSettings() {}
}
