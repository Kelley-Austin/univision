public with sharing class ContentDocumentLinkTriggerHandler {

    public static void afterInsert(List<ContentDocumentLink> links) {
        Set<Id> contentDocIds = new Set<Id>();
        Map<Id, Id> docToLinkedEntity = new Map<Id, Id>();

        for (ContentDocumentLink cdl : links) {
            String entityType = cdl.LinkedEntityId.getSObjectType().getDescribe().getName();
            if (entityType == 'Source_System__c') {
                contentDocIds.add(cdl.ContentDocumentId);
                docToLinkedEntity.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
            }
        }

        if (contentDocIds.isEmpty()) return;

        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocIds AND IsLatest = true
        ];

        for (ContentVersion cv : versions) {
            String ext = cv.FileExtension?.toLowerCase();
            if (ext == null || !new Set<String>{'csv', 'tsv', 'txt'}.contains(ext)) continue;
            Id sourceSystemId = docToLinkedEntity.get(cv.ContentDocumentId);
            if (sourceSystemId != null) {
                System.enqueueJob(new IngestQueueable(cv.Id, sourceSystemId));
            }
        }
    }
}
