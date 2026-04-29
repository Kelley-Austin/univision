public with sharing class MatrixSyncInvocable {

    // ── Trigger Manual Sync ──────────────────────────────────────────────────

    public class TriggerRequest {
        @InvocableVariable(label='Unused — leave blank')
        public String unused;
    }

    @InvocableMethod(
        label='Trigger Manual Matrix Inventory Sync'
        description='Enqueues MatrixInventorySyncQueueable to run immediately. Use in the Admin Sync Screen Flow.'
    )
    public static List<String> triggerSync(List<TriggerRequest> requests) {
        System.enqueueJob(new MatrixInventorySyncQueueable(true));
        return new List<String>{ 'Sync queued successfully.' };
    }

    // ── Reschedule Nightly Job ───────────────────────────────────────────────

    public class RescheduleRequest {
        @InvocableVariable(label='Schedule Hour (0–23 UTC)' required=true)
        public Integer scheduleHour;
    }

    public class RescheduleResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='Reschedule Matrix Nightly Sync'
        description='Aborts the existing nightly sync job and reschedules it at the given UTC hour (0–23).'
    )
    public static List<RescheduleResult> reschedule(List<RescheduleRequest> requests) {
        List<RescheduleResult> results = new List<RescheduleResult>();
        for (RescheduleRequest req : requests) {
            RescheduleResult res = new RescheduleResult();
            try {
                MatrixInventoryScheduler.scheduleAt(req.scheduleHour);
                res.success = true;
                res.message = 'Sync rescheduled to run daily at ' + req.scheduleHour + ':00 UTC.';
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    // ── Get Schedule Info ────────────────────────────────────────────────────

    public class ScheduleInfoRequest {
        @InvocableVariable(label='Unused — leave blank')
        public String unused;
    }

    public class ScheduleInfoResult {
        @InvocableVariable(label='Is Scheduled')
        public Boolean isScheduled;

        @InvocableVariable(label='Next Fire Time')
        public Datetime nextFireTime;

        @InvocableVariable(label='Next Fire Time (formatted)')
        public String nextFireTimeText;
    }

    @InvocableMethod(
        label='Get Matrix Sync Schedule Info'
        description='Returns whether the nightly sync job is currently scheduled and when it will next run.'
    )
    public static List<ScheduleInfoResult> getScheduleInfo(List<ScheduleInfoRequest> requests) {
        ScheduleInfoResult result = new ScheduleInfoResult();

        List<CronTrigger> cts = [
            SELECT NextFireTime FROM CronTrigger
            WHERE CronJobDetail.Name = :MatrixInventoryScheduler.JOB_NAME
            AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 1
        ];

        result.isScheduled = !cts.isEmpty();
        if (!cts.isEmpty()) {
            result.nextFireTime = cts[0].NextFireTime;
            result.nextFireTimeText = cts[0].NextFireTime != null
                ? cts[0].NextFireTime.format('EEE, MMM d yyyy h:mm a z')
                : 'Unknown';
        } else {
            result.nextFireTimeText = 'Not scheduled';
        }

        return new List<ScheduleInfoResult>{ result };
    }
}
