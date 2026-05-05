@isTest
public with sharing class LogX_Test {

    @TestSetup
    static void setup(){

        for(integer i=0;i<205;i++){
            LogX.LogProcessHandlers.add(new LogXEventHandlers__mdt(
                Type__c='all',
                Invoke__c='Class',
                EventName__c='LogX_LogEvent'+i,
                DeveloperName='TestProcessor'+i,
                Handler__c='LogX_LogProcessor'+i,
                ProcessOrder__c=i,
                IsActive__c=true
                ));
        }
    }

    @isTest
    static void basicTest() {
        //emit a log event
        Log lg = LogX.logEvent('LogX_LogEvent', 'message', null);
        lg.type = 'LogThenCallout';
        lg.emit();
        Test.startTest();        
            Test.getEventBus().deliver();
        Test.stopTest();
        //verify that the Log__c record has been created
        system.Assert.areEqual(1, LogX.getAllLogs().size());
    } 

    @isTest
    static void basicFlowTest() {
        //emit a log event
        Log lg = LogX.logEvent('LogX_Flow', 'message', null);
        Log lg2 = LogX.logEvent('LogX_Flow', 'message', null);
        Test.startTest();
            Log.emit(new List<Log>{lg,lg2});        
            Test.getEventBus().deliver();
        Test.stopTest();
        //verify that the Log__c records have been created. 
        //two initial and the one response
        system.Assert.areEqual(3, LogX.getAllLogs().size());
    } 

    @isTest
    static void testLogDetailInserts() {
        //emit a log event
        Log lg = LogX.logEvent('LogX_LogEvent', 'LogX_LogEvent message', null);
        Log lgD1 = LogX.logEvent('LogX_LogEvent', 'LogX_LogEvent Detail message', lg.correlationId);
        Log lg2 = LogX.logEvent('LogX_LogEvent', 'LogX_LogEvent Detail message 2', lg.correlationId);
        Log lgD2 = LogX.logEvent('LogX_LogEvent', 'LogX_LogEvent Detail message 3', lg.correlationId);
        Test.startTest();
            Log.emit(new List<Log>{lg,lgD1,lg2,lgD2});        
            Test.getEventBus().deliver();
        Test.stopTest();
        //check the log and details
        Map<String, LogDetail__c> logDs = LogX.getAllLogDetails();
        System.Assert.areEqual(3, logDs.size());

        Log lg3 = LogX.logEvent('LogX_LogEvent', 'LogX_LogEvent Detail message 4', lg.correlationId);
        lg3.emit();
        Test.getEventBus().deliver();
        logDs = LogX.getAllLogDetails();
        System.Assert.areEqual(4, logDs.size());
    }

    @isTest
    static void testBulkLogInserts() {
        //emit log events
        List<Log> logs = new List<Log>();
        for(Integer i=0; i<150; i++) {
            Log lg = LogX.logEvent('LogX_LogEvent', 'LogX_LogEvent message', null);
            logs.add(lg);
        }
        Test.startTest();
            Log.emit(logs);        
            Test.getEventBus().deliver();
        Test.stopTest();
        //check the log and details
        System.Assert.areEqual(150, LogX.getAllLogs().size());

    }

    @isTest
    static void testBulkLogInsertsMultipleHandlers() {
        //emit log events
        List<Log> logs = new List<Log>();
        for(Integer i=0; i<150; i++) {
            Log lg = LogX.logEvent('LogX_LogEvent'+i, 'LogX_LogEvent message ' + i, null);
            logs.add(lg);
        }
        for(integer i=0;i<205;i++){
            LogX.LogProcessHandlers.add(new LogXEventHandlers__mdt(
                Type__c='all',
                Invoke__c='Class',
                EventName__c='LogX_LogEvent'+i,
                DeveloperName='TestProcessor'+i,
                Handler__c='LogX_LogProcessor'+i,
                ProcessOrder__c=i,
                IsActive__c=true
                ));
        }
        Test.startTest();
            Log.emit(logs);        
            Test.getEventBus().deliver();
        Test.stopTest();
        //check the log and details
        System.Assert.areEqual(150, LogX.getAllLogs().size());
    }

    @isTest
    static void testNineLogInsertsMultipleHandlers() {
        //emit log events
        List<Log> logs = new List<Log>();
        for(Integer i=0; i<9; i++) {
            Log lg = LogX.logEvent('LogX_LogEvent'+i, 'LogX_LogEvent message ' + i, null);
            logs.add(lg);
        }
        Test.startTest();
            Log.emit(logs);        
            Test.getEventBus().deliver();
        Test.stopTest();
        //check the log and details
        System.Assert.areEqual(9, LogX.getAllLogs().size());
    }

    @isTest
    static void testBulkLogInsertsMultipleHandlersError() {
        //emit log events
        Map<String,List<Log>> logMap = new Map<String,List<Log>>();
        for(Integer i=0; i<220; i++) {
            Log lg = LogX.logEvent('LogX_LogEvent'+i, 'LogX_LogEvent message ' + i, null);
            logMap.put('LogX_LogEvent'+i,new List<Log>{lg});
        }
        LogDispatcher ld = new LogDispatcher(logMap);    
        Test.startTest();
            ld.processLogs();        
        Test.stopTest();
        //check the log there should be one exception log
        Map<string,Log__c> logs = LogX.getAllLogs();
        System.Assert.areEqual(1, logs.size());
        System.Assert.areEqual('Exception', logs.values()[0].LogEventName__c);
    }

    @isTest
    static void testEnqueueMultipleHandlers() {
        //emit log events
        Map<String,List<Log>> logMap = new Map<String,List<Log>>();
        for(Integer i=0; i<9; i++) {
            Log lg = LogX.logEvent('LogX_LogEvent'+i, 'LogX_LogEvent message ' + i, null);
            lg.Type = 'Response';
            logMap.put('LogX_LogProcessor'+i,new List<Log>{lg});
        }
        Test.startTest();
            LogX.enqueueJob(new LogDispatcher(logMap));
            Test.getEventBus().deliver();
        Test.stopTest();
        //check the log and details
        System.Assert.areEqual(9, LogX.getAllLogs().size());
    }
    @isTest
    static void testEnqueueMultipleHandlersError() {
        //emit log events
        Map<String,List<Log>> logMap = new Map<String,List<Log>>();
        for(Integer i=0; i<9; i++) {
            Log lg = LogX.logEvent('LogX_LogEvent'+i, 'LogX_LogEvent message ' + i, null);
            lg.Type = 'Response';
            logMap.put('Fail'+i,new List<Log>{lg});
        }
        Test.startTest();
            LogX.enqueueJob(new LogDispatcher(logMap));
            Test.getEventBus().deliver();
        Test.stopTest();
        //check that no logs were created
        System.Assert.areEqual(0, LogX.getAllLogs().size());
    }

    @IsTest
    static void testTestResponse(){
        RESTHandlerMock thisMock = new RESTHandlerMock();
        Test.setMock(HttpCalloutMock.class, thisMock);
        String namedCredential = '';
        String callMethod = 'GET';
        String path = 'https://th-apex-http-callout.herokuapp.com/animals';
        String data = 'animals';
        RESTHandler controller = new RESTHandler(namedCredential, callMethod, path, data);
        controller.request.testResponseBody = 'test';
        
        HttpResponse resp = controller.doCallout();
        system.assertEquals('test', resp.getBody(),'Expected body to be [test] but was ['+resp.getBody()+']');
        
        // second instance of call with a header
        List<RESTHandler.HTTPHeader> customHeaders = new List<RESTHandler.HTTPHeader>();
        RESTHandler.HTTPHeader sampleHeader = new RESTHandler.HTTPHeader();
        sampleHeader.name = 'Content-type';
        sampleHeader.value = 'application/json';
        customHeaders.add(sampleHeader);

        RESTHandler controller2 = new RESTHandler(namedCredential, callMethod, path, data);
        controller2.request.headers = customHeaders;
        controller2.request.testResponseBody = 'test';
        controller2.request.timeout = 0;
        HttpResponse resp2 = controller2.doCallout();
        system.assertEquals('test', resp2.getBody(),'Expected body to be [test] but was ['+resp2.getBody()+']');

        //third instance with no testResponse
        RESTHandler controller3 = new RESTHandler(namedCredential, callMethod, null, null);
        controller3.request.timeout = 2;
        HttpResponse resp3 = controller3.doCallout();
        system.assertEquals(thisMock.body, resp3.getBody(),'Expected body to be ['+thisMock.body+'] but was ['+resp3.getBody()+']');


        //fourth instance forcing Disabled check
        RESTHandler controller4 = new RESTHandler(namedCredential, callMethod, null, null);
        controller4.request.testResponseBody = 'ForceDisabled';
        RESTHandler.Response resp4 = controller4.wrapCallout();
        system.assertEquals('Callouts Disabled', resp4.body,'Expected body to be [Callouts Disabled] but was ['+resp4.body+']');
    }

    @IsTest
    static void testUtilityMethods(){
        String guid = LogX.getGuid();
        system.assertNotEquals(null,guid,'LogX.getGuid() did not return a value');
        UUID uuidR = LogX.getUuid();
        system.assertNotEquals(null,uuidR, 'LogX.getUuid() did not return a value');

        String orgName = LogX.orgName();
        system.assertNotEquals(null,orgName, 'LogX.orgName() did not return a value');

        Boolean isProd = LogX.isProd();
        system.assertNotEquals(null, isProd, 'LogX IsProd logic not performing');
        isProd = LogX.isProd(); //should pull from cache
        system.assertNotEquals(null, isProd, 'LogX IsProd logic not performing');
        
        String settingResult = LogX.getParam('fail');
        system.assertEquals(null, settingResult, 'LogX failed to return null for a missing param');

        Integer intFailResult = LogX.getParamInt('fail');
        system.assertEquals(0, intFailResult, 'LogX failed to return 0 for a missing param');
        intFailResult = LogX.getParamInt('OrgName');
        system.assertEquals(0, intFailResult, 'LogX failed to return 0 for a missing param');

        Integer intResult = LogX.getParamInt('CacheTimeout');
        system.assertNotEquals(0, intResult, 'LogX failed to return a valid integer for CacheTimeout');

        String orgResult = LogX.getParam('OrgName');
        system.assertNotEquals('', orgResult, 'LogX failed to return a valid OrgName');

        orgResult = LogX.getParam('OrgName'); //should pull from cache 
        system.assertNotEquals('', orgResult, 'LogX failed to return a valid OrgName');

        orgResult = LogX.getParam('OrgName','dev'); //should pull from dev 
        system.assertNotEquals(null, orgResult, 'LogX failed to return a valid OrgName');
        orgResult = LogX.getParam('OrgName','qa'); //should pull from qa 
        system.assertNotEquals(null, orgResult, 'LogX failed to return a valid OrgName');
        orgResult = LogX.getParam('OrgName','uat'); //should pull from dev 
        system.assertNotEquals(null, orgResult, 'LogX failed to return a valid OrgName');
        try{
            orgResult = LogX.getParam('OrgName','usupportedOrg'); //should throw an exception
        } catch(Exception ex){
            system.Assert.isTrue(ex.getMessage().contains('Unsupported org'), 'LogX failed to throw an exception');
        }
        
    
        //force incorrect orgName evaluation by inserting false orgNames in the cache. This bruteforces the OrgType and IsProd test results
        Cache.clear();
        Cache.put('LogXInternal_ThisOrgName', 'FalseORG--Sandb', 3600);  // Cache the result.
        orgName = LogX.orgName(); //should pull from cache
        system.assertNotEquals(null, orgName, 'LogX -- logic failed');
        //wipe the cache just to be sure
        Boolean cacheRemoval = cache.remove('thiswillfail');
        system.assertEquals(false,cacheRemoval,'LogX.cache.remove should have failed but did not.');
        cacheRemoval = cache.remove('LogXInternal_ThisOrgName');
        system.assertEquals(true,cacheRemoval,'LogX.cache.remove failed.');

        Cache.clear();

        //additional cache testing
        Integer tInt = 23459;
        Decimal tDec = 223445.78;
        Long tLint = 4271990;
        cache.put('testInt',tInt);
        system.assertEquals(23459,cache.getInt('testInt'),'cache.getInt failed to return a valid integer.');
        cache.put('testDec',tDec);
        system.assertEquals(223445.78,cache.getDec('testDec'),'cache.getDec failed to return a valid integer.');
        cache.put('testLint',tLint);
        system.assertEquals(4271990,cache.getLInt('testLint'),'cache.getLInt failed to return a valid integer.');
        Datetime tDtt = System.now();
        cache.put('testDtt',tDtt);
        system.assertEquals(tDtt,cache.getDTT('testDtt'),'cache.getDTT failed to return a valid integer.');
        cache.put('testDt',tDtt.date());
        system.assertEquals(tDtt.date(),cache.getDT('testDt'),'cache.getDT failed to return a valid integer');
        system.assertEquals(true,cache.contains('testDt'),'cache.contains failed to return a valid response.');
        system.assertEquals(null,cache.getObj('testDt_fail'),'cache.get returned incorrect value when invalid key was passed.');
        cache.put('testDt_notAMap',tDtt.date());
        system.assertEquals(null,cache.getObj(null),'cache.get returned incorrect value when null was passed.');
        system.assertEquals(null,cache.getObj(' _ '),'cache.get returned incorrect value when underscore was passed.');
        system.assertEquals(false,cache.remove('testDt_fail'),'cache.remove failure test failed.');
        system.assertEquals(false,cache.remove(''),'cache.remove blank test failed.');
        system.assertEquals(false,cache.remove(' _ '),'cache.remove underscore test failed.');

    }


    @IsTest
    
    static void soqlTests(){
        test.startTest();
            list<sobject> testObjs = LogX.getObjects('User');
            system.Assert.areNotEqual(0, testObjs.size());

            testObjs = logX.getObjects('User', 'WHERE name = \'ssdsncncjsjshgxxtt122344ssdfc\'');
            system.Assert.areEqual(0, testObjs.size());

            String testResult = LogX.getSelectStar('User');
            system.Assert.areNotEqual(0,testResult.length());

            List<String> testList = LogX.getFieldNamesList('User');
            Set<String> testSet = LogX.getFieldNames('User');
            system.Assert.areNotEqual(0,testList.size());
            system.Assert.areNotEqual(0,testSet.size());

            map<string,string> testMap = LogX.getFieldLabelsMap('User',true);
            system.Assert.areNotEqual(0,testMap.size());

            testList = LogX.getFieldLabelsList('User',true);
            system.Assert.areNotEqual(0,testList.size());

            testResult = LogX.getSelectStarSOQL('User');
            system.Assert.areNotEqual(0,testResult.length());

            testList = LogX.getFieldNamesList('User',true);
            system.Assert.areNotEqual(0,testList.size());
            
        test.stopTest();
         
    }

@IsTest
static void sobjectUpdate(){
    test.startTest();
        Log__c lg = new Log__c();
        insert lg;
        LogDetail__c lgd = new LogDetail__c();
        lgd.Log__c = lg.Id;
        insert lgd;
    test.stopTest();
    System.Assert.areEqual(1,LogX.getAllLogs().size());
    
    Map<Id,Map<String,String>> mappedValues = new Map<Id,Map<String,String>>();
    Map<String,string> fieldMap = new Map<String,string>();
    fieldMap.put('isBatch__c', 'true');
    fieldMap.put('CorrelationId__c', 'adsjmdkasnmdklasnkl');
    fieldMap.put('TriggerSize__c', '20');
    fieldMap.put('Log__c', lg.Id);
    fieldMap.put('Mantissa__c','0.1212445');
    fieldMap.put('ComposedDateTime__c',System.now().toString());
    fieldMap.put('ExpirationDate__c',System.now().date().toString());
    mappedvalues.put(lgd.Id ,fieldMap);   
    LogX.updateSobject('LogDetail__c', mappedValues); 
    fieldMap.put('ComposedDateTime__c','this will fail');
    LogX.updateSobject('LogDetail__c', mappedValues);
    LogX.updateSobject('FailState', mappedValues);
    LogX.getObjects('FailState', New List<Id>());
}

    @IsTest
    static void testVirtuals(){
        TriggerHandler th = new TriggerHandler();
        th.beforeInsert(null);
        th.afterInsert(null);
        th.beforeUpdate(null,null);
        th.afterUpdate(null,null);
        th.beforeDelete(null);
        th.afterDelete(null);
        th.afterUndelete(null);
    }

    public class CustomException extends Exception{} 

    @IsTest
    static void testException(){
       
        // testing logMessage method
        logX.logEvent('eventName1', 'eventMessage', 'eventContent');
        logX.logEvent('eventName2', 'eventMessage', 'eventContent','correlationId');
        logX.logEvent('eventName3', 'eventMessage', 'eventKey', 'eventContent','correlationId');
        logX.logEvent('eventName4', 'eventType', 'eventMessage', 'eventKey', 'eventContent','correlationId');
        

        test.startTest();
            logX.logEvent('eventName5', 'eventType', 'eventMessage', 'eventKey', 'eventContent','correlationId', true, true);
            logX.logEvent('eventName6', 'eventType', 'eventMessage', 'eventKey', 'eventContent','correlationId', true, false);
            logX.logException(new customException(),'message'); 

            List<customException> excs = new List<customException>();
            customException ce =  new customException('test');
            excs.add(ce);
            logX.logExceptions(excs,'message');
            logX.logExceptions(excs,'message','testID',true);
            logX.debug('logdebug', new list<Object>(), true);
        test.stopTest();

        System.Assert.areEqual(2, LogX.getAllLogs().size());

    }

    @IsTest
    static void testDatabaseErrors(){
        // call logService.logErrors

        test.startTest();
            //generate some errors
            List<Account> accounts = new List<Account>();
            for(integer i=0 ; i < 5 ; i++){
                Account acc = new Account();
                accounts.add(acc);
            }
            List<Database.SaveResult> results = database.insert(accounts, false);
            List<Database.error> errs = new List<Database.error>();
            // Inspect the errors
            for (Database.SaveResult sr : results) {
                Database.Error singleErr = null;
                for(Database.Error err : sr.getErrors()) {
                    errs.add(err);
                    singleErr = err;
                }
                logX.logError(singleErr, 'message');
            }
            LogX.logErrors(errs,'message');
        test.stopTest();
        System.Assert.areEqual(10,LogX.getAllLogs().size());
    }

    @IsTest
    static void testDeletion(){
        test.startTest();
            Log__c log = new Log__c();
            log.type__c = 'DELETE';
            log.CorrelationID__c = 'test';
            insert log;
            ScheduleDeleteLogs s = new ScheduleDeleteLogs();
            s.execute(null);
        test.stopTest();
        System.Assert.areEqual(0, LogX.getAllLogs().size());
    }

    @IsTest
    static void publishemptyLogEvent(){
        LogEvent__e lge = new LogEvent__e();
        EventBus.publish(lge);
        System.Assert.areEqual(0, LogX.getAllLogs().size());
    }

    @IsTest
    static void getLimits(){
        system.assert.areNotEqual(null,LimitStatus.stringVal);
    }



}