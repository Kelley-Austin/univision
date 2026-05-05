/**
 * =============================================================================
 *  TriggerHandler — Base class for all Apex trigger handler implementations
 * =============================================================================
 *
 *  Why this exists
 *  ---------------
 *  Without a shared base class, every trigger handler reinvents:
 *    * the Trigger.isBefore / isInsert / etc. dispatch ladder
 *    * a recursion / bypass mechanism
 *    * a way to identify itself for logs and telemetry
 *  That repetition is where bugs live. This base class centralizes the
 *  dispatch and the bypass logic so concrete handlers only have to think about
 *  the business rules for their object.
 *
 *  Concrete-handler shape
 *  ----------------------
 *      public with sharing class FooTriggerHandler extends TriggerHandler {
 *          protected override void beforeInsert() { ... }
 *          protected override void afterUpdate()  { ... }
 *      }
 *
 *  And the trigger stays a 3-line dispatcher:
 *      trigger FooTrigger on Foo__c (
 *          before insert, before update, before delete,
 *          after  insert, after  update, after  delete
 *      ) {
 *          new FooTriggerHandler().run();
 *      }
 *
 *  Bypass mechanism
 *  ----------------
 *  Some service-layer code (e.g. data backfills, the Period Close service,
 *  reconciliation seed loads) needs to suppress trigger logic for a scoped
 *  block of work. Use:
 *      TriggerHandler.bypass('FooTriggerHandler');
 *      try { ... do system work ... }
 *      finally { TriggerHandler.clearBypass('FooTriggerHandler'); }
 *
 *  Bypasses are stored in a static Set scoped to the current transaction.
 *  ALWAYS clear them in a finally block so an exception doesn't leave a
 *  handler permanently bypassed for the rest of the transaction.
 *
 *  Recursion control
 *  -----------------
 *  This base class does NOT implement automatic recursion suppression
 *  (i.e. "skip if already running for these record IDs"). That logic is
 *  intentionally omitted because:
 *    * It hides genuine recursive bugs.
 *    * Real recursion control belongs in the specific phase that recurses,
 *      not at the dispatch layer.
 *  If a concrete handler needs recursion control for a specific phase, it
 *  should track its own per-record-ID set in a static field on that handler.
 *
 *  Testing
 *  -------
 *  See TriggerHandlerTest for end-to-end coverage of dispatch + bypass.
 * =============================================================================
 */
public virtual class TriggerHandler {

    // ─── Bypass registry ──────────────────────────────────────────────────────
    // Kept private to prevent ad-hoc mutation; use the public bypass() / clearBypass() API.
    // @TestVisible so tests can introspect / reset between methods.
    @TestVisible
    private static Set<String> bypassedHandlers = new Set<String>();

    /**
     * Suppress all phase methods for the named handler until clearBypass() is
     * called. Identifier is the concrete handler's class name (matches the
     * value returned by getHandlerName()).
     */
    public static void bypass(String handlerName) {
        if (String.isBlank(handlerName)) return;
        bypassedHandlers.add(handlerName);
    }

    /**
     * Re-enable phase methods for the named handler. Always pair with bypass()
     * inside a try / finally so an exception cannot leave a handler bypassed
     * for the remainder of the transaction.
     */
    public static void clearBypass(String handlerName) {
        if (String.isBlank(handlerName)) return;
        bypassedHandlers.remove(handlerName);
    }

    /**
     * Reset the bypass registry. Provided for tests that share static state.
     */
    @TestVisible
    private static void clearAllBypasses() {
        bypassedHandlers.clear();
    }

    /**
     * True if the named handler is currently bypassed.
     */
    public static Boolean isBypassed(String handlerName) {
        return bypassedHandlers.contains(handlerName);
    }

    // ─── Dispatch ─────────────────────────────────────────────────────────────

    /**
     * Single entry point invoked by the trigger. Routes to the appropriate
     * phase override based on Trigger context. No-op when called outside of a
     * trigger context (defensive — a misuse, but cheap to guard).
     */
    public void run() {
        // Skip if explicitly bypassed by service-layer code in this transaction.
        if (isBypassed(getHandlerName())) return;

        // Defensive: if for some reason this is called outside a trigger,
        // do nothing rather than throw.
        if (!Trigger.isExecuting) return;

        if (Trigger.isBefore) {
            if (Trigger.isInsert) beforeInsert();
            if (Trigger.isUpdate) beforeUpdate();
            if (Trigger.isDelete) beforeDelete();
        } else if (Trigger.isAfter) {
            if (Trigger.isInsert)   afterInsert();
            if (Trigger.isUpdate)   afterUpdate();
            if (Trigger.isDelete)   afterDelete();
            if (Trigger.isUndelete) afterUndelete();
        }
    }

    // ─── Phase methods (no-op defaults; concrete handlers override) ──────────
    // virtual + protected: only this class and subclasses can call them, and
    // subclasses can replace any subset without re-declaring all of them.

    protected virtual void beforeInsert()  {}
    protected virtual void beforeUpdate()  {}
    protected virtual void beforeDelete()  {}
    protected virtual void afterInsert()   {}
    protected virtual void afterUpdate()   {}
    protected virtual void afterDelete()   {}
    protected virtual void afterUndelete() {}

    // ─── Identification ──────────────────────────────────────────────────────

    /**
     * Returns the concrete subclass's name, used as the bypass key.
     * Default extracts the class name from the runtime type description
     * (e.g. "ActualRevenueTriggerHandler:[...]" → "ActualRevenueTriggerHandler").
     * Subclasses can override if they need a different identifier.
     */
    protected virtual String getHandlerName() {
        return String.valueOf(this).split(':')[0];
    }
}
