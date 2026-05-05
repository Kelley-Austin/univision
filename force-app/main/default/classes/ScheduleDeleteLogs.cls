/** 
* Basic scheduler for the Delete Logs Queueable.
* @author Patrick Stephens
* @version 1.0 
*/
public without sharing class ScheduleDeleteLogs implements Schedulable  {
    public void execute(SchedulableContext SC) {
        LogX.enqueueJob(new QueueableDeleteLogs());
    }
}

    /*
        Sample code to schedule daily at 5am. Run the following in Execute anonymous to schedule the job
    
        ScheduleDeleteLogs m = new ScheduleDeleteLogs();
        String sch = '0 0 05 * * ?';
        String jobID = system.schedule('Delete Logs', sch, m);
        
    */