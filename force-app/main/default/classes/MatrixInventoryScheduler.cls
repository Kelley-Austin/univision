/**
 * Scheduled Apex that enqueues MatrixInventorySyncQueueable every 15 minutes.
 *
 * Salesforce only allows one execution per cron expression, so achieving a
 * 15-minute interval requires four separate scheduled jobs — one for each
 * quarter-hour mark.  Call MatrixInventoryScheduler.scheduleAll() once from
 * Anonymous Apex (or a post-install script) to register all four jobs:
 *
 *   MatrixInventoryScheduler.scheduleAll();
 *
 * To verify the jobs were created: Setup → Scheduled Jobs → filter for "Matrix".
 * To remove them: Setup → Scheduled Jobs → delete all four "Matrix Inventory Sync" entries.
 */
public class MatrixInventoryScheduler implements Schedulable {

    // How far back to look for changes on each run.
    // 20 minutes gives a buffer in case a job fires slightly late.
    private static final Integer LOOKBACK_MINUTES = 20;

    public void execute(SchedulableContext ctx) {
        Datetime since = Datetime.now().addMinutes(-LOOKBACK_MINUTES);
        System.enqueueJob(new MatrixInventorySyncQueueable(since));
    }

    /**
     * Registers four cron jobs that together fire every 15 minutes.
     * Safe to call multiple times — will throw a duplicate-name error if
     * the jobs already exist, so check Setup → Scheduled Jobs first.
     */
    public static void scheduleAll() {
        Map<String, String> jobs = new Map<String, String>{
            'Matrix Inventory Sync :00' => '0 0 * * * ?',
            'Matrix Inventory Sync :15' => '0 15 * * * ?',
            'Matrix Inventory Sync :30' => '0 30 * * * ?',
            'Matrix Inventory Sync :45' => '0 45 * * * ?'
        };
        for (String name : jobs.keySet()) {
            System.schedule(name, jobs.get(name), new MatrixInventoryScheduler());
        }
    }
}
