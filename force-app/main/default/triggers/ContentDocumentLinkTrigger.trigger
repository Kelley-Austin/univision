/**
 * ContentDocumentLinkTrigger — 3-line dispatcher; delegates to
 * ContentDocumentLinkTriggerHandler via TriggerDispatcher (canonical Patrick
 * Stephens framework). This is the entry point for the upload-driven ingest
 * pipeline.
 *
 * Subscribed only to afterInsert because CDL is effectively insert-only —
 * Salesforce creates a link once when a file is shared with a record. If
 * the model ever changes (e.g. unlinking should detach a queued ingest)
 * add the relevant phase here AND override the matching method on the
 * handler.
 */
trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {
    TriggerDispatcher.run(new ContentDocumentLinkTriggerHandler(), 'ContentDocumentLinkTrigger');
}
