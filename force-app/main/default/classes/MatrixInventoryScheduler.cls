public class MatrixInventoryScheduler implements Schedulable {

    public static final String JOB_NAME = 'Matrix Inventory Nightly Sync';

    public void execute(SchedulableContext ctx) {
        System.enqueueJob(new MatrixInventorySyncQueueable(false));
    }

    /**
     * Aborts any existing nightly sync job and schedules a new one at the given UTC hour (0–23).
     * Reads the configured hour from Matrix_Sync_Config__mdt if no override is passed.
     */
    public static void scheduleAtConfiguredHour() {
        List<Matrix_Sync_Config__mdt> cfg = [
            SELECT Schedule_Hour__c FROM Matrix_Sync_Config__mdt
            WHERE DeveloperName = 'Default' LIMIT 1
        ];
        Integer hour = (!cfg.isEmpty() && cfg[0].Schedule_Hour__c != null)
            ? Integer.valueOf(cfg[0].Schedule_Hour__c)
            : 2;
        scheduleAt(hour);
    }

    public static void scheduleAt(Integer hour) {
        if (hour == null || hour < 0 || hour > 23) {
            throw new IllegalArgumentException('hour must be 0–23, got: ' + hour);
        }
        abortExisting();
        String cron = '0 0 ' + hour + ' * * ?';
        System.schedule(JOB_NAME, cron, new MatrixInventoryScheduler());
    }

    public static void abortExisting() {
        List<CronTrigger> existing = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 10
        ];
        for (CronTrigger ct : existing) {
            System.abortJob(ct.Id);
        }
    }

    public static Datetime getNextFireTime() {
        List<CronTrigger> cts = [
            SELECT NextFireTime FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 1
        ];
        return cts.isEmpty() ? null : cts[0].NextFireTime;
    }

    public static Boolean isScheduled() {
        return !([
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 1
        ].isEmpty());
    }
}
