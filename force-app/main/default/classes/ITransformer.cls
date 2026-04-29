/**
 * Contract that every source-system transformer must fulfil.
 * Implementations receive raw file bytes plus the Source_System__c Id
 * and return a list of populated Inbound_Staging__c sObjects ready for upsert.
 */
public interface ITransformer {
    /**
     * @param fileContent  Raw bytes from the uploaded file (may be UTF-8, UTF-16, or CP1252).
     * @param sourceSystemId  Id of the Source_System__c config record for this load.
     * @param dryRun  When true, rows are returned but NOT inserted — used by the Mapping Rule Editor preview.
     * @return Staging rows (Status = Pending or Excluded); caller performs upsert on External_Key__c.
     */
    List<Inbound_Staging__c> transform(Blob fileContent, Id sourceSystemId, Boolean dryRun);
}
