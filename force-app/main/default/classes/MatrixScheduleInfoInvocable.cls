public with sharing class MatrixScheduleInfoInvocable {

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
