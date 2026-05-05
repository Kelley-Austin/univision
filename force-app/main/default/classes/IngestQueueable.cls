public class IngestQueueable implements Queueable {
    private Id contentVersionId;
    private Id sourceSystemId;

    public IngestQueueable(Id contentVersionId, Id sourceSystemId) {
        this.contentVersionId = contentVersionId;
        this.sourceSystemId = sourceSystemId;
    }

    public void execute(QueueableContext ctx) {
        new IngestService().processUpload(contentVersionId, sourceSystemId);
    }
}
