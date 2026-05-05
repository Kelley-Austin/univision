/**
 * Runs PacingSnapshotBatch daily. To schedule at 2 AM:
 *   System.schedule('Pacing Snapshot Daily', '0 0 2 * * ?', new PacingSnapshotScheduler());
 */
public class PacingSnapshotScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PacingSnapshotBatch(), 200);
    }
}
