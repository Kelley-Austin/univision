public without sharing class QueueableDeleteLogs implements Queueable{

    public List<Log__c> logList {get;set;}

    public queueableDeleteLogs() {
        Integer archVal = 30;
        try{
            archval = Integer.valueOf(Logx.getParam('ArchiveInDays'));
        } catch (Exception ex){
            LogX.logException(ex, 'Invalid value in ArchiveInDays General Setting.',null);
        }
        Datetime archDate = System.now()-archVal;
        logList = [SELECT Id, CreatedDate
                                            FROM Log__c
                                            WHERE CreatedDate < :archDate OR type__c = 'DELETE' LIMIT 9999];
        
        System.debug(loggingLevel.info, 'instantiate logList.size::'+logList.size());
    }
    
    public void execute(QueueableContext context) {              
        System.debug(loggingLevel.info, 'Execute logList.size::'+logList.size());
        if(logList.Size()>0){
            Database.delete( logList, false);
            Database.emptyRecycleBin(logList);
            LogX.debug(loglist.size() + ' Logs Deleted.');
            if(logList.size()==9999){
                LogX.enqueueJob(new QueueableDeleteLogs());
            }
        }
        
    }
}