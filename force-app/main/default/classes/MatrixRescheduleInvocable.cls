public with sharing class MatrixRescheduleInvocable {

    public class RescheduleRequest {
        @InvocableVariable(label='Schedule Hour (0-23 UTC)' required=true)
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
        description='Aborts the existing nightly sync job and reschedules it at the given UTC hour (0-23).'
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
}
