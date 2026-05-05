/**
 * =============================================================================
 *  TriggerHandlerTest
 * =============================================================================
 *
 *  Covers the dispatch + bypass mechanics of TriggerHandler in isolation, with
 *  no dependency on any sObject's metadata. We use a private inner subclass
 *  that records which phases were invoked so we can assert dispatch behavior.
 *
 *  Note: full afterX dispatch (which requires Trigger.isExecuting == true) is
 *  exercised by the concrete handler tests — e.g. ActualRevenueTriggerHandlerTest.
 *  Here we focus on the bypass registry and the no-op-when-not-in-trigger guard.
 * =============================================================================
 */
@IsTest
private class TriggerHandlerTest {

    // ─── Test fixture: a probe subclass that records which phases ran ────────
    private class ProbeHandler extends TriggerHandler {
        public Integer beforeInsertCount = 0;
        public Integer afterInsertCount  = 0;

        protected override void beforeInsert() { beforeInsertCount++; }
        protected override void afterInsert()  { afterInsertCount++;  }
    }

    // ─── Bypass registry: add ────────────────────────────────────────────────

    @IsTest
    static void bypass_registers_handler_name() {
        TriggerHandler.clearAllBypasses();

        Assert.isFalse(TriggerHandler.isBypassed('FooHandler'),
            'Should not be bypassed before bypass() is called');

        TriggerHandler.bypass('FooHandler');

        Assert.isTrue(TriggerHandler.isBypassed('FooHandler'),
            'Should be bypassed after bypass() is called');
    }

    // ─── Bypass registry: clear ──────────────────────────────────────────────

    @IsTest
    static void clearBypass_removes_handler_name() {
        TriggerHandler.clearAllBypasses();
        TriggerHandler.bypass('BarHandler');

        TriggerHandler.clearBypass('BarHandler');

        Assert.isFalse(TriggerHandler.isBypassed('BarHandler'),
            'clearBypass should remove the handler from the registry');
    }

    // ─── Bypass: blank / null inputs are ignored ─────────────────────────────

    @IsTest
    static void bypass_ignores_blank_input() {
        TriggerHandler.clearAllBypasses();

        TriggerHandler.bypass(null);
        TriggerHandler.bypass('');
        TriggerHandler.bypass('   ');

        Assert.isFalse(TriggerHandler.isBypassed(''),
            'Blank handler names should never enter the registry');
    }

    // ─── run() outside trigger context is a no-op (defensive guard) ──────────

    @IsTest
    static void run_outside_trigger_is_noop() {
        TriggerHandler.clearAllBypasses();
        ProbeHandler probe = new ProbeHandler();

        // Calling run() in a plain test method (no Trigger.isExecuting) should
        // not throw and should not invoke any phase method.
        probe.run();

        Assert.areEqual(0, probe.beforeInsertCount,
            'run() outside a trigger should not dispatch beforeInsert');
        Assert.areEqual(0, probe.afterInsertCount,
            'run() outside a trigger should not dispatch afterInsert');
    }

    // ─── getHandlerName returns concrete subclass name ───────────────────────

    @IsTest
    static void getHandlerName_returns_subclass_name() {
        TriggerHandler.clearAllBypasses();

        // Use a probe that exposes the protected method via a public accessor.
        // (Apex doesn't allow @TestVisible on protected methods cross-class,
        // so we wrap via an inner subclass.)
        NamedProbeHandler h = new NamedProbeHandler();

        Assert.areEqual('NamedProbeHandler', h.exposeName(),
            'Default getHandlerName should match the simple class name');
    }

    private class NamedProbeHandler extends TriggerHandler {
        public String exposeName() { return getHandlerName(); }
    }
}
