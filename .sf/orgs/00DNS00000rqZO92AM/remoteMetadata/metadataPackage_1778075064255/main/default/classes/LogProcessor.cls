public virtual class LogProcessor implements ILogProcessor {
    public List<Log> logs {get;set;}

    public LogProcessor() {
        logs = new List<Log>();
    }

    public virtual LogProcessor.Result processLogs(){
        LogProcessor.Result result = new LogProcessor.Result(logs, Test.IsRunningTest() ? true : false);
        return result;
    } 

    public virtual Log processLog(Log lg){
        return lg;
    }

    public LogProcessor setLogs(List<Log> logList){
            this.logs = logList;
            return this;
    }

    public void cacheEventKeys(){
        for(Log lg:logs){
            lg.cacheEventKey();
        }
    }
    public void cacheEventKeys(Integer ttl){
        for(Log lg:logs){
            lg.cacheEventKey(ttl);
        }
    }
    public void clearCachedEventKeys(){
        for(Log lg:logs){
            lg.clearCachedEventKey();
        }
    }
    
    public class Result{
        public Boolean emitOnFinalize {get;set;}

        public Result(List<Log> resultLogs){
            this(resultLogs, true);
        }

        public Result(List<Log> resultLogs, Boolean emitOnFinalize){
            this(resultLogs, emitOnFinalize, false);
        }

        public Result(List<Log> resultLogs, Boolean emitOnFinalize, Boolean emitResultImmediately){
            this.resultLogs = resultLogs;
            this.emitImmediately = emitResultImmediately;
            this.emitOnFinalize = emitOnFinalize;
        }

        public Boolean emitImmediately {get;set;} 
        public Integer totalProcessed {get{return resultLogs.size();}}
        public List<Log> resultLogs {get;set;}
        public List<Log> exceptionLogs {get;set;}
        public void finalize(){
            if(this.emitOnFinalize){
                if(this.emitImmediately || Test.isRunningTest()){
                    if(resultLogs!=null) Log.emitIM(resultLogs);
                    if(exceptionLogs!=null) Log.emitIM(exceptionLogs);
                } else {
                    if(resultLogs!=null) Log.emit(resultLogs);
                    if(exceptionLogs!=null) Log.emit(exceptionLogs);
                }
            }
        }
    }

}