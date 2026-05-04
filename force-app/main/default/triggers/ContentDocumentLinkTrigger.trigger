trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {
    ContentDocumentLinkTriggerHandler.afterInsert(Trigger.new);
}
