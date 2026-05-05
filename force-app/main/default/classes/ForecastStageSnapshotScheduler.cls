/**
 * Schedulable that fires every Sunday at 23:59 in the org's locale timezone
 * (Univision's org is configured to America/New_York, so this is Sunday-EOD ET).
 * It enqueues ForecastStageSnapshotQueueable with that day's date as the
 * Snapshot_Date__c.
 */
public class ForecastStageSnapshotScheduler implements Schedulable {

    public static final String JOB_NAME = 'Forecast Stage Sunday Snapshot';

    /** Apex cron for Sunday 23:59 in org TZ. Sec Min Hr ? * DOW (Sun=1) */
    public static final String CRON_SUNDAY_2359 = '0 59 23 ? * 1';

    public void execute(SchedulableContext ctx) {
        System.enqueueJob(new ForecastStageSnapshotQueueable(Date.today()));
    }

    public static void schedule() {
        abortExisting();
        System.schedule(JOB_NAME, CRON_SUNDAY_2359, new ForecastStageSnapshotScheduler());
    }

    public static void abortExisting() {
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
              AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 10
        ]) {
            System.abortJob(ct.Id);
        }
    }

    public static Boolean isScheduled() {
        return !([
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
              AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 1
        ].isEmpty());
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
}
