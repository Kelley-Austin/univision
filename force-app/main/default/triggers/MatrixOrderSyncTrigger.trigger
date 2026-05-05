/**
 * MatrixOrderSyncTrigger — 3-line dispatcher for the Matrix_Order_Sync__e
 * platform event. Logic lives in MatrixOrderSyncTriggerHandler.
 *
 * Platform Event triggers only fire on afterInsert; no other phase is
 * available. The handler bypass mechanism (TriggerHandler.bypass(...)) still
 * works here, which is useful for data-loader-style operations that want
 * to suppress the outbound callout while replaying historic state.
 */
trigger MatrixOrderSyncTrigger on Matrix_Order_Sync__e (after insert) {
    new MatrixOrderSyncTriggerHandler().run();
}
