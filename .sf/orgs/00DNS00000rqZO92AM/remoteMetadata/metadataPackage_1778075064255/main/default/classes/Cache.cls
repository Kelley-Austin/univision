/** 
* Manipulates the LogXCache to store key, validation, and 
* correlation values during processing to manage duplication 
* @author Patrick Stephens
* @version 1.0 
*/
public without sharing class Cache {
    // Custom exception class for Cache-related errors
    public class CacheException extends Exception {}

    // Default time-to-live for cache entries, in seconds
    public static final Integer TTLSECONDS = 3600;
    public static final Integer TTLMAX = 36000;

    // Cached partition for storing key-value pairs
    public static Cache.OrgPartition valueMap {
        get{
            // Initialize valueMap if it is null
            if(valueMap == null) {
                valueMap = Cache.Org.getPartition('local.LogXCache');
            }
            return valueMap;
        }
        set;
    }

    /**
     * Puts an object into the cache with a specified time-to-live.
     * @param key The key under which the object is stored
     * @param obj The object to store
     * @param ttl The time-to-live for the cache entry, in seconds
     */
    public static void put(String key, Object obj, Integer ttl){
        // Only proceed if the key is not blank
        if(String.isNotBlank(key)){
            // Convert key to lowercase for case-insensitive storage
            key = key.toLowerCase();
            if(key.contains('_')){
                //This should be placed as a key in a map inside the cache
                List<String> mKeys = key.split('_');
                if(String.isNotBlank(mKeys[0]) && String.isNotBlank(mKeys[1])){
                    if(!valueMap.contains(mKeys[0])){
                        valueMap.put(mKeys[0], new Map<String,Object>(),TTLMax);
                    }
                    Boolean isMap = (valueMap.get(mKeys[0]) instanceOf Map<String,Object>);
                    if(!isMap){
                        valueMap.put(mKeys[0], new Map<String,Object>(),TTLMax);
                    }
                    Map<String,Object> cm = (Map<String,Object>)valueMap.get(mKeys[0]);    
                    cm.put(mKeys[1],obj);
                    valueMap.put(mKeys[0],cm);
                    system.debug(logginglevel.INFO, 'Cache Map Loaded for ' + key);
                }
            } else {
                valueMap.put(key, obj, ttl);
                system.debug(logginglevel.INFO, 'Cache Loaded for ' + key);
            }
        }
    }
    
    /**
     * Puts an object into the cache with the default time-to-live.
     * @param key The key under which the object is stored
     * @param obj The object to store
     */
    public static void put(String key, Object obj){
        put(key, obj, TTLSECONDS);
    }
    
    /**
     * Checks if a single key exists in the cache.
     * @param key The key to check
     * @return True if the key exists, false otherwise
     */
    public static Boolean contains(String key){
        if(String.isNotBlank(key)){
            // Convert key to lowercase for case-insensitive lookup
            key = key.toLowerCase();
            if(key.contains('_')){
                //This should be a key in a map inside the cache
                List<String> mKeys = key.split('_');
                if(String.isNotBlank(mKeys[0]) && 
                    String.isNotBlank(mKeys[1]) && 
                    valueMap.contains(mKeys[0])){
                        Map<String,Object> cm = (Map<String,Object>)valueMap.get(mKeys[0]);
                        return cm.containsKey(mKeys[1]);
                    }
            } else {
                return valueMap.contains(key);
            }
        }
        system.debug(logginglevel.INFO, 'Cache contains request is empty ' + key);
        return false;
    }
    
    /**
     * Removes a key from the cache.
     * @param key The key to remove
     * @return True if the key was removed, false otherwise
     */
    public static Boolean remove(String key){
        if(String.isNotBlank(key)){
            // Convert key to lowercase for case-insensitive removal
            key = key.toLowerCase();
            if(key.contains('_')){
                //This should be a key in a map inside the cache
                List<String> mKeys = key.split('_');
                if(String.isNotBlank(mKeys[0]) && 
                    String.isNotBlank(mKeys[1]) && 
                    valueMap.contains(mKeys[0])){
                        Map<String,Object> cm = (Map<String,Object>)valueMap.get(mKeys[0]);
                        if(cm.containsKey(mKeys[1])){
                            cm.remove(mKeys[1]);
                            return true;
                        }
                } else {
                    system.debug(logginglevel.INFO, 'Cache removal failed. Map not found for ' + key);
                    return false;
                }
            } else {
                return valueMap.remove(key);
            }
        }
        system.debug(logginglevel.INFO, 'Cache removal failed. Key not found for ' + key);
        return false;
    } 
    
    /**
     * Clears the cache.
     * @return True if the key was removed, false otherwise
     */
    public static void clear(){
        for(String key : valueMap.getKeys()){
            remove(key);
        } 
    } 
    
    /**
     * Retrieves a string object from the cache.
     * @param key The key of the string object to retrieve
     * @return The string object associated with the key
     */
    public static String getStr(String key){
        return (String)getObj(key);
    }
    
    /**
     * Retrieves an integer object from the cache.
     * @param key The key of the integer object to retrieve
     * @return The integer object associated with the key
     */
    public static Integer getInt(String key){
        return (Integer)getObj(key);
    }
    
    /**
     * Retrieves a datetime object from the cache.
     * @param key The key of the datetime object to retrieve
     * @return The datetime object associated with the key
     */
    public static Datetime getDTT(String key){
        return (Datetime)getObj(key);
    }
    
    /**
     * Retrieves a date object from the cache.
     * @param key The key of the date object to retrieve
     * @return The date object associated with the key
     */
    public static Date getDT(String key){
        return (Date)getObj(key);
    }
    
    /**
     * Retrieves a decimal object from the cache.
     * @param key The key of the decimal object to retrieve
     * @return The decimal object associated with the key
     */
    public static Decimal getDec(String key){
        return (Decimal)getObj(key);
    }
    
    /**
     * Retrieves a long integer object from the cache.
     * @param key The key of the long integer object to retrieve
     * @return The long integer object associated with the key
     */
    public static Long getLInt(String key){
        return (Long)getObj(key);
    }
    
    /**
     * Retrieves a boolean object from the cache.
     * @param key The key of the boolean object to retrieve
     * @return The boolean object associated with the key
     */
    public static Boolean getBool(String key){
        return (Boolean)getObj(key);
    }
    
    /**
     * Retrieves an object from the cache based on the key.
     * @param key The key of the object to retrieve
     * @return The object associated with the key, or null if the key is blank
     */
    public static Object getObj(String key){
        if(String.isNotBlank(key)){
            // Convert key to lowercase for case-insensitive retrieval
            key = key.toLowerCase();
            if(key.contains('_')){
                //This should be a key in a map inside the cache
                List<String> mKeys = key.split('_');
                if(String.isNotBlank(mKeys[0]) && String.isNotBlank(mKeys[1])){
                    if(valueMap.contains(mKeys[0])){
                        if(valueMap.get(mKeys[0]) instanceOf Map<String,Object>){
                            Map<String,Object> cm = (Map<String,Object>)valueMap.get(mKeys[0]);
                            return cm.get(mKeys[1]);
                        } else {
                            system.debug(logginglevel.INFO, 'Cache Requested an Invalid Type. ' + key);
                            return null;
                        }
                    } else {
                        //system.debug(logginglevel.INFO, 'Cache not found. ' + key);
                        return null;
                    }
                }else {
                    system.debug(logginglevel.INFO, 'Cache Requested nothing. ' + key);
                    return null;
                }
            }
            return valueMap.get(key);
        }
        system.debug(logginglevel.INFO, 'Cache Requested null. ' + key);
        return null;
        
    }

    public static integer getIterator(String key){
        if(String.isBlank(key)){return -1;}
        if(key.contains('-'))
            key = key.replace('-', '');
        if(valueMap.contains(key)){
            integer i = (Integer)valueMap.get(key);
            valueMap.put(key, i+1);
            return i+1;
        } else {
            valueMap.put(key, 0);
            return 0;
        }
    }
}