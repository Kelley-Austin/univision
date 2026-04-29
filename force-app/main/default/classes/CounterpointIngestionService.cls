/**
 * Invocable action that kicks off CounterpointIngestionBatch for a given
 * Salesforce File (ContentVersion).
 *
 * Call from a Flow's Action element after a file is uploaded to Salesforce Files.
 * The batch runs asynchronously — the Flow does not wait for it to complete.
 *
 * Input: Content Version ID of the uploaded Counterpoint CSV.
 */
public class CounterpointIngestionService {

    public class IngestRequest {
        @InvocableVariable(label='Content Version ID' description='ID of the ContentVersion record for the uploaded Counterpoint CSV file.' required=true)
        public Id contentVersionId;
    }

    @InvocableMethod(
        label='Ingest Counterpoint File'
        description='Parses a Counterpoint sales order CSV (calendar or broadcast date variant) and upserts Actuals Records. Runs as an async batch job.'
        category='Advertising'
    )
    public static void ingestCounterpointFile(List<IngestRequest> requests) {
        for (IngestRequest req : requests) {
            ContentVersion cv = [
                SELECT Title
                FROM   ContentVersion
                WHERE  Id = :req.contentVersionId
                LIMIT  1
            ];
            Database.executeBatch(
                new CounterpointIngestionBatch(req.contentVersionId, cv.Title),
                200
            );
        }
    }
}
