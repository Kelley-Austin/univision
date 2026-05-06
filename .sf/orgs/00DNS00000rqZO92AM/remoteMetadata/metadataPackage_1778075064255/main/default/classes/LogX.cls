/** 
* This class provides utility functionality to the LogX framework
* @author Patrick Stephens
* @version 1.0 
*/
public without sharing class LogX {
//LOGGING WRAPPERS    

    /**
     * Logs a generic event by wrapping it into a Log object.
     * Overloaded methods.
     *
    * @param eventName      Name of the event
    * @param type           Custom type of the event (e.g., "Info", "Error")
    * @param message        Message describing the event
    * @param eventKey       Key or identifier for the event
    * @param content        Additional content (e.g., JSON or text details)
    * @param correlationId  Correlation identifier for tracking
    * @param doEmit         If true, the log will be emitted
    * @param emitImmediately If true, the log is emitted immediately instead of being queued
    * @return A new Log object representing the logged event
    */
    public static Log logEvent(String eventName, String message, String correlationId){  
        return logEvent(eventName, message, null, correlationId);
    }
    public static Log logEvent(String eventName, String message, String content, String correlationId){  
        return logEvent(eventName, message, null, content, correlationId);
    }
    public static Log logEvent(String eventName, String message, String eventKey, String content, String correlationId){  
        return logEvent(eventName, null, message, eventKey, content, correlationId);
    }
    public static Log logEvent(String eventName, String type, String message, String eventKey, String content, String correlationId){
        return logEvent(eventName, type, message, eventKey, content, correlationId, false, false);
    } 
    public static Log logEvent(String eventName, String type, String message, String eventKey, String content, String correlationId, Boolean doEmit, Boolean emitImmediately){
        Log newLog = new Log(eventName, type, message, eventKey, content, correlationId);
        if(doEmit){
            //check cache for eventKey 
            if(String.isNotBlank(eventKey)){
                if(cache.contains(eventKey)){
                    return newLog;
                }
                cache.put(eventKey, system.now());
            }
            if(emitImmediately){
                newLog.emitIM();
            } else {
                newLog.emit();
            }
        }
        return newLog;
    }

    /**
     * Log single or multiple exceptions with a custom message, correlationId, 
     * and a flag to emit logs immediately or not.
     * overloaded methods
     * 
     * @param excs          A list of exceptions to log
     * @param message       Custom message to include in each log
     * @param correlationId Correlation identifier for tracking
     * @param doEmit        If true, emits the log immediately
     */
    public static Log logException(Exception exc, String message){
        return logException(exc, message,null);
    }
    public static Log logException(Exception exc, String message, String correlationId){
        return new Log('Exception', String.valueOf(exc.getTypeName()), message + ' : ' + exc.getMessage(), null, exc.getStackTraceString(), correlationId);
    }
    public static void logException(Exception exc, String message, String correlationId, Boolean doEmit){
        List<Exception> excs = new List<Exception>();
        excs.add(exc);
        logExceptions(excs,message,correlationId, doEmit);
    }
    public static Log logException(String message, String type, string content, string correlationID){
        return new Log('Exception', type, message, null, content, correlationId);
    }
    public static void logExceptions(List<Exception> excs, String message){
        logExceptions(excs,message,null);
    }
    public static List<Log> logExceptions(List<Exception> excs, String message, String correlationId){
        List<Log> logs = new List<log>();
        if(excs!=null){
            String jsonObj = null;
            for(Exception ex : excs){
                jsonObj += message + '\n';
                Log newLog = new Log('Exception', String.valueOf(ex.getTypeName()), message + ' : ' + ex.getMessage(), null, ex.getStackTraceString(), correlationId);
                logs.add(newLog);
            }
        }
        return logs;
    }
    public static void logExceptions(List<Exception> excs, String message, String correlationId, Boolean doEmit){
        if(excs!=null){
            if(doEmit)
                Log.emitIM(logExceptions(excs, message, correlationId));
        }
    }

    /**
     * Log single or multiple Database.error objects with a message and correlationId.
     * Overloaded methods.
     * 
     * @param errs          A list of Database.error instances to log
     * @param message       A custom message to log with these errors
     * @param correlationId Correlation identifier for tracking
     */
    public static void logError(Database.error err, String message){
        logError(err,message,null);
    }
    public static void logError(Database.error err, String message, String correlationId){
        List<Database.error> errs = new List<Database.error>();
        errs.add(err);
        logErrors(errs,message,null);
    }
    public static void logErrors(List<Database.error> errs, String message){
        logErrors(errs,message,null);    
    }
    public static void logErrors(List<Database.error> errs, String message, String correlationId){
        if(errs!=null){
            List<Log> logs = new List<log>();
            String jsonObj = null;
            for(Database.error err : errs){
                jsonObj = JSON.serializePretty(err); 
                Log newLog = new Log('DatabaseError', String.valueOf(err.getStatusCode()), message, null, jsonObj, correlationId);
                logs.add(newLog);
            }
            Log.emit(logs);
        }
    }

    /**
     * Outputs a debug message along with a list of objects and controls whether or not to create a Log record.
     * Overloaded methods.
     * 
     * @param message The message to log
     * @param objs    List of objects to be serialized and appended to debug
     * @param logThis If true, creates a Log record for immediate emission
     */
    public static void debug(String message){
        debug(message, null);
    }
    public static void debug(String message, object obj){
        debug(message, obj, false);
    }
    public static void debug(String message, object obj, Boolean logThis){
        List<Object> objs = new List<Object>();
        objs.add(obj);
        debug(message, objs, false);
    }
    public static void debug(String message, List<object> objs, Boolean logThis){
        String composedMessage = '\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n';
        composedMessage += '------------------------------------------------------------\n';
        composedMessage += message + '\n';
        String jsonObj = null;
        List<Log> debugLogs = new List<Log>();
        for(Object obj:objs){
            Log debugLog = null;
            if(obj!=null){
                try{
                    jsonObj = JSON.serializePretty(obj); 
                } catch(Exception ex){
                    jsonObj = '**************************************************************\n'; 
                    jsonObj += 'Unable to serialize object ' + obj.toString();
                    jsonObj += '\n**************************************************************\n'; 
                }
                composedMessage += '------------------------------------------------------------\n';
                composedMessage += jsonObj + '\n';
                debugLog = new Log('Debug', obj.toString(), jsonObj, null, jsonObj, null);
            } else{
                debugLog = new Log('Debug', null, message, null, null, null);
            }
            debugLogs.add(debugLog);
        }   
        composedMessage += '------------------------------------------------------------\n';
        composedMessage += '------------------------------------------------------------';
        System.debug(LoggingLevel.INFO, composedMessage);
        if(debugLogs!=null && logThis){
            Log.emitIM(debugLogs);
        }
    }



//UTILITY METHODS   
    /**
     * Custom exception thrown when a required parameter is missing from the LogX cache.
     */
    public class LogXNoParamFoundException extends Exception{}
        
    /**
     * General exception class for LogX-related errors.
     */
    public class LogXException extends Exception{}

    /**
     * Time-to-live parameter for cached data.
     */
    public static final Integer TTLPARAM = 3600;

    /**
     * Enqueues a Queueable job if daily async limits are not hit, otherwise logs an Exception event.
     *
     * @param queueableClass The Queueable class instance to be enqueued
     * @return The job ID if enqueued successfully, or null if limit is reached
     */
    public static Id enqueueJob(Queueable queueableClass){
        if(LimitStatus.isLimitHit('DailyAsyncApexExecutions')){
            LogX.logEvent('Exception', 'AsyncLimitException', 'Org AsyncLimit reached: ' + LimitStatus.getLimitValue('DailyAsyncApexExecutions') + ' out of ' + LimitStatus.getLimitTotal('DailyAsyncApexExecutions') + '.' , null, LimitStatus.stringVal, null, true,true);
            return null;
        } else {
            return System.enqueueJob(queueableClass);
        }
    }
    

    

    /**
     * Generates a globally unique identifier (GUID) by creating a cryptographic key and converting it to a formatted string.
     * @return A new GUID in the format xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
     */
    public static String getGuid(){
        return getUUID().toString();
    } 
    public static UUID getUUID(){
        return UUID.randomUUID();
    } 

    /**
     * Determines if the current user is the process user, based on a parameter from the cache.
     * @return Boolean indicating if the current user is the process user.
     */
    public static Boolean isProcessUser{
        get{
            if(isProcessUser == null){  // If isProcessUser is not yet initialized.
                String param = getParam('ProcessUser');  // Fetch the ProcessUser parameter.
                if(param.contains('*'))
                    param = param.replace('*', orgName());  // Replace '*' in the parameter with the organization's name.
                isProcessUser = (UserInfo.getUserName().equalsIgnoreCase(param));  // Compare current user name with the parameter.
            }
            return isProcessUser;
        }
        set;
    }

    /**
     * Retrieves a parameter value from the LogX cache. If the value is not present in the cache, fetches it from another source.
     * @param paramName The name of the parameter to retrieve.
     * @return The value of the parameter or null if not found.
     */
    @TestVisible
    public static String getParam(String paramName){
        if(String.isNotBlank(paramName)){  // Check if the parameter name is valid.
            String val = Cache.getStr('LogXInternalParam_' + paramName);  // Try to retrieve from the cache.
            if(val != null){
                return val;
            }
            val = getParam(paramName, orgType());  // Fetch parameter based on org type.
            if(val!=null){
                Cache.put('LogXInternalParam_' + paramName, val,TTLPARAM);  // Store in cache for future use.
                return val;
            }
        } 
        //logX.debug('LogX Parameter not found for request: ' + paramName);
        return null;
        
    }
    /**
     * Overloaded to return an Integer
     */
    public static Integer getParamInt(String paramName){
        try{
            String param = getParam(paramName);
            if(string.isBlank(param)){
                return 0;
            }
            Integer i = Integer.valueOf(param);
            return i;
        } catch (Exception ex){
            debug('LogX.getParamInt(paramName) Unable to convert the parameter value to an integer. ' + ex.getMessage());
            return 0;
        }
    }

    /**
     * Determines the type of the current organization (e.g., DEV, QA, UAT, PROD).
     * @return The organization type as a string.
     */
    @TestVisible
    public static String orgType(){
        if(Cache.contains('LogXInternal_ThisOrgType')){  // Check if org type is cached.
            return Cache.getStr('LogXInternal_ThisOrgType');  // Return cached org type.
        } else {
            String result = null;
            LogXParameter__mdt logxParam = LogXParameter__mdt.getInstance('OrgName');  // Retrieve org name from metadata.
            if(logxParam == null){
                throw new LogXNoParamFoundException('The OrgName parameter was not found in the LogXParameter__mdt custom metadata.');
            } else {
                String thisOrg = orgName();  // Get current organization name.
                // Compare current org name with predefined values and assign org type.
                if(thisOrg.equalsIgnoreCase(logxParam.DevValue__c)){
                    result = 'DEV';
                } else if(thisOrg.equalsIgnoreCase(logxParam.QAValue__c)){
                    result =  'QA';
                } else if(thisOrg.equalsIgnoreCase(logxParam.UATValue__c)){
                    result = 'UAT';
                } else if(thisOrg.equalsIgnoreCase(logxParam.PRODValue__c)){
                    result = 'PROD';
                } else {
                    throw new LogXNoParamFoundException('The current org, ' + thisOrg + ' is not present in the OrgName parameter.');
                }
                Cache.put('LogXInternal_ThisOrgType', result, TTLPARAM);  // Cache the result for future use.
                return result;
            }
        }
    }

    /**
     * Retrieves a parameter value based on the organization type.
     * @param paramName The name of the parameter.
     * @param org The type of organization (DEV, QA, UAT, PROD).
     * @return The parameter value or null if not found.
     */
    @TestVisible
    public static String getParam(String paramName, String org){
        String result = null;
        if(String.isNotBlank(paramName) && String.isNotBlank(org)){
            LogXParameter__mdt logxParam = LogXParameter__mdt.getInstance(paramName);  // Retrieve parameter from metadata.
            if(logxParam != null){
                // Assign parameter value based on the organization type.
                switch on org.toLowerCase() {
                    when 'dev'{
                        result = logxParam.DevValue__c;
                    }
                    when 'qa'{
                        result = logxParam.QAValue__c;
                    }
                    when 'uat'{
                        result = logxParam.UATValue__c;
                    }
                    when 'prod'{
                        result = logxParam.ProdValue__c;
                    }
                    when else {
                        throw new LogXException('Unsupported org: ' + org + '.');
                    }
                }
            }
        }
        return result;
    }

    /**
     * Determines if the current environment is a production environment.
     * @return True if the current environment is production, false otherwise.
     */
    @TestVisible
    public static Boolean isProd(){
        if(Cache.contains('LogXInternal_ThisOrgIsProd')){  // Check if prod status is cached.
            return Cache.getBool('LogXInternal_ThisOrgIsProd');  // Return cached prod status.
        } else {
            boolean isSB = true;
            String server = System.url.getOrgDomainUrl().getHost().toLowerCase();  // Get the current org domain URL.
            if(server.contains('sandbox')){
                isSB = true;
            } else {
                server = server.split('\\.')[0];
                if(server.contains('--') || server == 'tapp0'){
                    isSB = true;
                } else if(server.length() > 2 && server.substring(0, 2) == 'cs'){
                    isSB = true;
                }
            }
            Boolean result = false;
            if(!isSB){
                result = (orgType() == 'PROD');  // Check if the org type is PROD.
            }
            Cache.put('LogXInternal_ThisOrgIsProd', result, TTLPARAM);  // Cache the result.
            return result;
        }
    }

    /**
     * Retrieves the current organization's name based on the domain URL.
     * @return The organization's name as a string.
     */
    @TestVisible
    public static String orgName(){
        if(Cache.contains('LogXInternal_ThisOrgName')){  // Check if org name is cached.
            return Cache.getStr('LogXInternal_ThisOrgName');  // Return cached org name.
        } else {
            String result = System.url.getOrgDomainUrl().getHost();  // Get the current org domain URL.
            if(result.contains('.')){
                result = result.split('\\.')[0];
                if(result.contains('--')){
                    result = result.split('--')[1];  // Extract org name if '--' is present in the URL.
                }
            }
            Cache.put('LogXInternal_ThisOrgName', result, TTLPARAM);  // Cache the result.
            return result;
        }
    }

    @TestVisible
    public static String getStateAbbr(String fullStateName){
        Schema.DescribeFieldResult fieldResult = User.statecode.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        for(Schema.PicklistEntry f : ple){
            if(f.getLabel().equalsIgnoreCase(fullStateName)){
                return f.getValue();
            }
        }
        return '';
    }

//GENERIC SOQL UTIL METHODS
    
    /**
     * Returns a list of field labels for the specified object type.
     * Optionally removes common system fields from the list.
     *
     * @param objectTypeName  The name of the SObject (e.g. 'Account')
     * @param removeSystemFields If true, excludes system fields from the result
     * @return List of field labels
     */
    public static List<string> getFieldLabelsList(string objectTypeName, boolean removeSystemFields){
        map<string, Schema.SObjectField> tMap = Schema.getGlobalDescribe().get(objectTypeName).getDescribe().fields.getMap();
        list<string> result = new list<string>();
        set<string> tSet = new set<String>{'name','setupownerid','id','isdeleted','ownerid','createdbyid','createddate','lastmodifiedbyid','lastmodifieddate','systemmodstamp'};
        
        for(string s : tMap.keySet()){
            // If we aren't removing system fields or this field isn't a system field, add it
            if(!removeSystemFields || !tSet.contains(s)){
                result.add(tMap.get(s).getDescribe().getLabel());
            }
        }
        return result;
    }

    /**
     * Returns a list of field API names for the specified object type.
     * Optionally removes common system fields from the list.
     *
     * @param objectTypeName    The name of the SObject (e.g. 'Account')
     * @param removeSystemFields If true, excludes system fields from the result
     * @return List of field names
     */
    public static List<string> getFieldNamesList(string objectTypeName, boolean removeSystemFields){
        set<string> tSet = Schema.getGlobalDescribe().get(objectTypeName).getDescribe().fields.getMap().keySet();
        if(removeSystemFields){
            tSet.removeAll(new List<String>{
                'name','setupownerid','id','isdeleted','ownerid','createdbyid','createddate',
                'lastmodifiedbyid','lastmodifieddate','systemmodstamp', 'lastvieweddate', 'lastreferenceddate'
            });
        }
        return new list<string>(tSet);
    }

    /**
     * Returns a list of all field names for the specified object type, including system fields.
     *
     * @param objectTypeName The name of the SObject
     * @return List of all field names
     */
    public static List<string> getFieldNamesList(string objectTypeName){
        return new list<string>(Schema.getGlobalDescribe().get(objectTypeName).getDescribe().fields.getMap().keySet());
    }

    /**
     * Returns a map of field API names to their labels for the specified object type.
     * Optionally removes common system fields.
     *
     * @param objectTypeName    The name of the SObject
     * @param removeSystemFields If true, excludes system fields from the result
     * @return A map where the key is the field API name and the value is the field label
     */
    public static map<string,string> getFieldLabelsMap(string objectTypeName, boolean removeSystemFields){
        map<string, Schema.SObjectField> tMap = Schema.getGlobalDescribe().get(objectTypeName).getDescribe().fields.getMap();
        map<string,string> result = new map<string,string>();
        set<string> tSet = new set<String>{'name','setupownerid','id','isdeleted','ownerid','createdbyid','createddate','lastmodifiedbyid','lastmodifieddate','systemmodstamp'};
        
        for(string s : tMap.keySet()){
            if(!removeSystemFields || !tSet.contains(s)){
                result.put(s,tMap.get(s).getDescribe().getLabel());
            }
        }
        return result;
    }

    /**
     * Retrieves the set of field names for the given SObject name.
     *
     * @param objectTypeName The name of the SObject
     * @return A set of field names
     */
    public static set<string> getFieldNames(string objectTypeName){
        return Schema.getGlobalDescribe().get(objectTypeName).getDescribe().fields.getMap().keySet();
    }

    /**
     * Retrieves the set of field names for the given SObjectType.
     *
     * @param objectType A Schema.SObjectType descriptor
     * @return A set of field names
     */
    public static set<string> getFieldNames(schema.SObjectType objectType){
        return objectType.getDescribe().fields.getMap().keySet();
    }

    /**
     * Constructs a SOQL query for all fields (equivalent to "SELECT *") for the given object type.
     * Excludes system fields by default set to false.
     *
     * @param objectTypeName The name of the SObject
     * @return A SOQL query string
     */
    public static string getSelectStarSOQL (string objectTypeName) {
        return getSelectStarSOQL(Schema.getGlobalDescribe().get(objectTypeName), false);
    }

    /**
     * Constructs a SOQL query for all fields (equivalent to "SELECT *") for the given object type.
     * If removeSystemFields is true, removes system fields from the query.
     *
     * @param objectTypeName     The name of the SObject
     * @param removeSystemFields If true, excludes common system fields from the query
     * @return A SOQL query string
     */
    public static string getSelectStarSOQL (string objectTypeName, boolean removeSystemFields) {
        return getSelectStarSOQL(Schema.getGlobalDescribe().get(objectTypeName), removeSystemFields);
    }

    /**
     * Constructs a SOQL query for all fields (equivalent to "SELECT *") for the given SObjectType.
     * Optionally excludes system fields.
     *
     * @param objectType         A Schema.SObjectType descriptor
     * @param removeSystemFields If true, excludes system fields from the query
     * @return A SOQL query string
     */
    public static String getSelectStarSOQL (Schema.SObjectType objectType, boolean removeSystemFields) {
        // Retrieve set of field names
        String selectStarSOQL;
        Set<String> objectFieldNames = new Set<String>();
        objectFieldNames = getFieldNames(objectType);
        
        // Remove system fields if requested
        if (removeSystemFields != null && removeSystemFields) {
            objectFieldNames.removeAll(new List<String>{
                'id','isdeleted','ownerid','createdbyid','createddate','lastmodifiedbyid','lastmodifieddate','systemmodstamp'
            });
        }
        selectStarSOQL = getSelectStar(objectFieldNames);
        selectStarSOQL += ' FROM ' + objectType.getDescribe().getName() + ' ';
        return selectStarSOQL;
    }

    /**
     * Constructs the SELECT portion of a SOQL query from a set of field names.
     *
     * @param strList A set of field names
     * @return The SELECT clause (e.g., "SELECT Id, Name, ...")
     */
    public static string getSelectStar(Set<string> strList){
        string result = 'SELECT ';
        for (String fieldName : strList) {
            result += fieldName + ', ';
        }
        // Remove the trailing comma and space, then return
        result = result.substring(0,result.length()-2) + ' ';
        return result;
    }

    /**
     * Shortcut method to construct the "SELECT *" style query for the provided object name.
     *
     * @param objectTypeName The name of the SObject
     * @return A SOQL query string selecting all fields
     */
    public static string getSelectStar(string objectTypeName){
        return getSelectStar(getFieldNames(Schema.getGlobalDescribe().get(objectTypeName)));
    }

    /**
     * Performs a dynamic SOQL query returning a list of SObjects for the given object type,
     * optionally filtered by a WHERE clause, and optionally removing system fields from the selection.
     *
     * @param objectTypeName    The name of the SObject
     * @param whereClause       Optional WHERE clause to filter the results
     * @param removeSystemFields If true, excludes system fields from the query
     * @return A list of SObjects matching the query
     */
    public static list<sobject> getObjects(string objectTypeName, string whereClause, boolean removeSystemFields){
        list<sobject> result = new list<sobject>();
        String message = objectTypeName + ' ' + objectTypeName;
        try{
            String soql = getSelectStarSOQL(objectTypeName, removeSystemFields);
            if(whereClause==null)
                whereClause='';
            message += '\n where: ' + ' ' + whereClause;
            
            // Perform the query
            result = database.query(String.escapeSingleQuotes(soql + ' ' + whereClause));
            message += '\n size: ' + ' ' + result.size();
        } catch (Exception ex){
            message = 'LogX.get Objects Exception: ' + ex.getMessage() + '\n' + message;
            logException(ex, message);
        }
        debug(message);
        return result;
    }

    /**
     * Returns all SObjects for a given type, removing system fields by default.
     *
     * @param objectTypeName The name of the SObject
     * @return A list of SObjects
     */
    public static list<sobject> getObjects(string objectTypeName){
        return getObjects(objectTypeName,null,true);
    }

    /**
     * Returns SObjects for a given type filtered by a custom WHERE clause, removing system fields by default.
     *
     * @param objectTypeName The name of the SObject
     * @param whereClause    The WHERE clause for filtering
     * @return A list of SObjects
     */
    public static list<sobject> getObjects(string objectTypeName, string whereClause){
        return getObjects(objectTypeName, WhereClause, true);
    }

    /**
     * Retrieves a list of SObjects based on a list of Ids.
     *
     * @param objectTypeName The name of the SObject
     * @param ids            List of record IDs to retrieve
     * @return A list of SObjects matching the provided IDs
     */
    public static list<sobject> getObjects(string objectTypeName, List<Id> ids){
        list<sobject> result = new list<sobject>();
        String message ='LogX.GetObjects: ' + objectTypeName + ' ' + objectTypeName;
        try{
            String soql = getSelectStarSOQL(objectTypeName, false);
            message += '\n where: ' + ' ' + 'WHERE id in :ids';
            
            // Dynamic query to retrieve records by ID
            result = database.query(String.escapeSingleQuotes(soql + ' ' + ' WHERE id in :ids'));
            message += '\n size: ' + ' ' + result.size();
        } catch (Exception ex){
            message = 'LogX.get Objects Exception: ' + ex.getMessage() + '\n' + message;
            logException(ex, message);
        }
        //debug(message);
        return result;
    }

    /**
     * Returns all Log__c records given a list of CorrelationIds.
     *
     * @param correlationIds The list of CorrelationIds
     * @return A list of Log__c records
     */
    public static Map<String,Log__c> getAllLogs(){
        return getLogs(null, true);
    }
    public static Map<String,Log__c> getLogs(Set<string> correlationIds){
        return getLogs(New List<String>(correlationIds), true);
        
    }
    public static Map<String,Log__c> getLogs(list<string> correlationIds,Boolean mapByCorrelationId){
        Map<String,Log__c> result = new Map<String,Log__c>();
        String message ='LogX.GetLogs: Log__c';
        try{
            String soql = getSelectStarSOQL('Log__c', false);
            if(correlationIds!=null){
                message += '\n where: WHERE CorrelationId in :correlationIds';
                soql += ' WHERE CorrelationId__c in :correlationIds';
            }
            // Dynamic query to retrieve records by CorrelationIds
            Map<String,Log__c> logs = new Map<String,Log__c>((List<Log__c>)database.query(String.escapeSingleQuotes(soql)));
            message += '\n size: ' + ' ' + result.size();
            if(mapByCorrelationId){
                for(Log__c log :logs.values()){
                    result.put(log.CorrelationId__c,log);
                }
            } else{
                result = logs;
            }
        } catch (Exception ex){
            message = 'LogX.getLogs Exception: ' + ex.getMessage() + '\n' + message;
            logException(ex, message);
        }
        //debug(message);
        return result;
    }

    /**
     * Returns all LogDetail__c records given a list of CorrelationIds.
     *
     * @param correlationIds The list of CorrelationIds
     * @return A list of LogDetail__c records
     */
    public static Map<String,LogDetail__c> getAllLogDetails(){
        return getLogDetails(null, false);
    }
    public static Map<String,LogDetail__c> getLogDetails(Set<string> correlationIds){
        return getLogDetails(New List<String>(correlationIds),false);
    }
    public static Map<String,LogDetail__c> getLogDetails(list<string> correlationIds,Boolean mapByCorrelationId){
        Map<String,LogDetail__c> result = new Map<String,LogDetail__c>();
        String message ='LogX.GetLogs: LogDetail__c';
        try{
            String soql = getSelectStarSOQL('LogDetail__c', false);
            if(correlationIds!=null){
                message += '\n where: WHERE CorrelationId in :correlationIds';
                soql += ' WHERE CorrelationId__c in :correlationIds';
            }
            // Dynamic query to retrieve records by CorrelationIds
            Map<String,LogDetail__c> logs = new Map<String,LogDetail__c>((List<LogDetail__c>)database.query(String.escapeSingleQuotes(soql)));
            if(mapByCorrelationId){
                for(LogDetail__c log :logs.values()){
                    result.put(log.CorrelationId__c,log);
                }
            } else{
                result = logs;
            }
            message += '\n size: ' + ' ' + result.size();
        } catch (Exception ex){
            message = 'LogX.getLogDetails Exception: ' + ex.getMessage() + '\n' + message;
            logException(ex, message);
        }
        //debug(message);
        return result;
    }

    /**
     * Sets field values on an SObject from a map of <FieldName, FieldValue>.
     *
     * @param obj        The SObject to populate
     * @param untypedMap Map of <FieldName, FieldValue> to set on the SObject
     */
    public static void setSobject(sObject obj, Map<String,Object> untypedMap){
        Map <String, Schema.SObjectField> objFieldMap = obj.getsObjectType().getDescribe().fields.getMap();
        
        // For each key in untypedMap, attempt to set the corresponding field on the SObject
        for(String fieldName : untypedMap.keySet()){
            if(objFieldMap.containsKey(fieldName) && untypedMap.get(fieldName)!=null){
                Schema.DescribeFieldResult dFr = objFieldMap.get(fieldName).getDescribe();
                try{
                    // Switch on field's data type to properly cast the value
                    switch on dFr.getType() {
                        when DATETIME {
                            DateTime dt = (DateTime)JSON.deserialize('"'+String.valueOf(untypedMap.get(fieldName))+'"', Datetime.class);
                            obj.put(fieldName, dt);
                        } when DATE {
                            try{
                                obj.put(fieldName, Date.parse(String.valueOf(untypedMap.get(fieldName))));
                            } catch(Exception e){
                                try{
                                    DateTime dt = (DateTime)JSON.deserialize('"'+String.valueOf(untypedMap.get(fieldName))+'"', Datetime.class);
                                    obj.put(fieldName, dt.date());
                                } catch(Exception ee){
                                    obj.put(fieldName, (Date)untypedMap.get(fieldName));
                                }
                            }
                        } when TIME {
                            DateTime dt = (DateTime)JSON.deserialize('"'+String.valueOf(untypedMap.get(fieldName))+'"', Datetime.class);
                            obj.put(fieldName, dt.time());
                        } when DOUBLE {
                            obj.put(fieldName, Double.valueOf(untypedMap.get(fieldName)));
                        } when CURRENCY, PERCENT {
                            obj.put(fieldName, Decimal.valueOf(String.valueOf(untypedMap.get(fieldName))));
                        } when INTEGER {
                            obj.put(fieldName, Integer.valueOf(untypedMap.get(fieldName)));
                        } when LONG {
                            obj.put(fieldName, Long.valueOf(String.valueOf(untypedMap.get(fieldName))));
                        } when BOOLEAN {
                            obj.put(fieldName, Boolean.valueOf(untypedMap.get(fieldName)));
                        } when BASE64, FLOATARRAY, LOCATION, SOBJECT {
                            // Do nothing or handle as needed
                            System.debug(LoggingLevel.INFO, 'Unhandled data type ' + dFr.getType() + ' for field ' + fieldName);
                        } when else {
                            // Fallback to string
                            obj.put(fieldName, String.valueOf(untypedMap.get(fieldName)));
                        }
                    }
                } catch(Exception ex){
                    LogX.debug('LogX.newSobject Exception for ' 
                               + obj.getSObjectType() 
                               + ' casting ' + fieldName 
                               + ' to type ' 
                               + objFieldMap.get(fieldName).getDescribe().getType(),ex);
                }
            }
        }
    }

    /**
     * Creates a new SObject of the specified type and sets its fields based on the provided map.
     *
     * @param objectTypeName The name of the SObject
     * @param untypedMap     A map of <FieldName, FieldValue> to set on the new SObject
     * @return A new SObject with fields populated from untypedMap
     */
    public static sObject newSobject(String objectTypeName, Map<String,Object> untypedMap){ 
        sObject result = Schema.getGlobalDescribe().get(objectTypeName).newSObject();
        LogX.setSobject(result, untypedMap);
        return result;
    }

    /**
     * Updates multiple SObjects of the specified type with the provided field values.
     *
     * @param objectTypeName    The name of the SObject
     * @param recordFieldValues A map of <Id, Map<FieldName, FieldValue>> indicating which fields to update for which records
     * @return A list of Database.SaveResult for each record update, or null if an exception occurs
     */
    public static List<Database.SaveResult> updateSobject(String objectTypeName, Map<Id,Map<String,Object>> recordFieldValues){
        try{
            // Collect the IDs to update
            list<Id> ids = new List<Id>(recordFieldValues.KeySet());
            // Retrieve the existing records
            List <SObject> sRecords = getObjects(objectTypeName,ids);

            // For each record, set new field values from recordFieldValues
            for(Sobject sObj : sRecords){
                setSobject(sObj, recordFieldValues.get(sObj.Id)); 
            }
            
            // Update and handle errors
            List<Database.SaveResult> results = database.update(sRecords);
            for (Database.SaveResult sr : results) {
                if (!sr.isSuccess()) {
                    LogX.logErrors(sr.getErrors(), 'Failure to update sobject ' + sr.getId());
                }
            }
            return results;
        }
        catch(Exception ex){
            LogX.logException(ex,'UpdateSobject exception occurred');
            return null;
        }
    }

    public static List<LogXEventHandlers__mdt> LogProcessHandlers {
        get{
            if(LogProcessHandlers == null){
                LogProcessHandlers = [SELECT Id, DeveloperName, EventName__c, Type__c, Handler__c, ProcessOrder__c, Invoke__c, ControlQueueing__c 
                                            FROM LogXEventHandlers__mdt 
                                            WHERE IsActive__c=True AND Extends__c='LogProcessor'
                                            ORDER BY ProcessOrder__c ASC];
            }
            return LogProcessHandlers;
        }
        set;
    }

    public static List<LogXEventHandlers__mdt> RequestProcessHandlers {
        get{ 
            if(RequestProcessHandlers==null){
                RequestProcessHandlers =[SELECT Id, DeveloperName, EventName__c, Type__c, Handler__c, ProcessOrder__c, Invoke__c, ControlQueueing__c 
                                                            FROM LogXEventHandlers__mdt 
                                                            WHERE IsActive__c=True AND Extends__c='RequestProcessor'
                                                            WITH USER_MODE
                                                            ORDER BY ProcessOrder__c ASC];
            }
            return RequestProcessHandlers;
        }
        set;
    }

    public static List<LogXEventHandlers__mdt> ResponseProcessHandlers {
        get{ 
            if(ResponseProcessHandlers==null){
                ResponseProcessHandlers =[SELECT Id, DeveloperName, EventName__c, Type__c, Handler__c, ProcessOrder__c, Invoke__c, ControlQueueing__c 
                                                            FROM LogXEventHandlers__mdt 
                                                            WHERE IsActive__c=True AND Extends__c='ResponseProcessor'
                                                            WITH USER_MODE
                                                            ORDER BY ProcessOrder__c ASC];
            }
            return ResponseProcessHandlers;
        }
        set;
    }

}