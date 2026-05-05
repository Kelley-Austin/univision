/**
 * MatrixOrderSyncTrigger — 3-line dispatcher for the Matrix_Order_Sync__e
 * platform event. Delegates to MatrixOrderSyncTriggerHandler via
 * TriggerDispatcher.
 *
 * Platform Event triggers only fire on afterInsert; no other phase is
 * available. The dispatcher's TriggerSetting__mdt-driven bypass mechanism
 * works here too, which is useful for data-loader-style operations that
 * want to suppress the outbound callout while replaying historic state.
 */
trigger MatrixOrderSyncTrigger on Matrix_Order_Sync__e (after insert) {
    TriggerDispatcher.run(new MatrixOrderSyncTriggerHandler(), 'MatrixOrderSyncTrigger');
}
