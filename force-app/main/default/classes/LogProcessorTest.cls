@IsTest
public class LogProcessorTest {
    
    @IsTest
    public static void processLogsTest(){
        LogProcessor lp = new LogProcessor();
        LogProcessor.Result result = lp.processLogs();
        result.finalize();
    }
    
    @IsTest
    public static void processLogTest(){
        LogProcessor lp = new LogProcessor();
        lp.processLog(new Log());
    }
    
    @IsTest
    public static void setLogsTest(){
        LogProcessor lp = new LogProcessor();
        lp.setLogs(new List<Log>());
    }
    
    @IsTest
    public static void cacheEventKeysTest(){
        LogProcessor lp = new LogProcessor();
        lp.cacheEventKeys();
        lp.cacheEventKeys(1);
    }
    
    @IsTest
    public static void clearCachedEventKeysTest(){
        LogProcessor lp = new LogProcessor();
        lp.clearCachedEventKeys();
    }
}