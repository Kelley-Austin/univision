public interface SourceSystemTransformer {
    List<Inbound_Staging__c> transform(String fileContent, Id loadBatchId, Id sourceSystemId, String sourceSystemCode);
}
