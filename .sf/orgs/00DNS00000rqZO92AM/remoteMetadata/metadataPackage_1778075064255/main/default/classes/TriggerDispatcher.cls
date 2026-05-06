/**
 * This class is responsible for dispatching trigger events to a provided TriggerHandler,
 * applying any applicable metadata-driven exclusions or exemptions (via TriggerSetting__mdt).
 * 
 * Usage:
 *  - Create a TriggerHandler class that extends the base TriggerHandler virtual class.
 *  - Call TriggerDispatcher.run(yourHandler, 'YourTriggerName') from within your trigger.
 * 
 * @author Patrick Stephens
 * @version 1.0 
 */
public without sharing class TriggerDispatcher {

    /**
     * Main dispatcher method that checks the TriggerSetting__mdt metadata for any exclusions
     * and exemptions, processes the records accordingly, and then invokes the relevant
     * TriggerHandler methods.
     *
     * @param handler     An instance of TriggerHandler (or a subclass) containing the trigger logic.
     * @param triggerName The name of the trigger to match in TriggerSetting__mdt records.
     */
    public static void run(TriggerHandler handler, String triggerName){

        // Retrieve all TriggerSetting__mdt records from the org (keyed by DeveloperName).
        Map<String,TriggerSetting__mdt> tss = TriggerSetting__mdt.getAll();

        // This set will collect any events or users that should be excluded based on metadata.
        Set<String> exclusionList = new Set<String>();

        // This map links field API names to sets of field values that should be excluded.
        Map<String,Set<String>> exclusionFieldValueMap = new Map<String,Set<String>>();

        // User exempt from certain exclusions (only one user can be exempt per setting).
        String exemptUser = null;

        // Clones of the Trigger context variables (to allow for removal of certain records).
        List<SObject> passedTriggerNew = null;
        Map<Id,SObject> passedTriggerNewMap = null;
        Map<Id,SObject> passedTriggerOldMap = null;

        // A cached set of field names used to verify if a field exists before applying exclusions.
        Set<String> objFieldNames = null;

        // Clone Trigger.new if available to avoid modifying the original context variables.
        if(Trigger.new != null){
            passedTriggerNew = Trigger.new.clone();
            // If field names haven't been retrieved yet, get them from the first record's SObjectType.
            if(objFieldNames == null)
                objFieldNames = LogX.getFieldNames(passedTriggerNew[0].getSObjectType());
        }

        // Clone Trigger.newMap if available.
        if(Trigger.newMap != null){
            passedTriggerNewMap = Trigger.newMap.clone();
            // Retrieve field names if they haven't been retrieved yet.
            if(objFieldNames == null)
                objFieldNames = LogX.getFieldNames(passedTriggerNewMap.values()[0].getSObjectType());
        }

        // Clone Trigger.oldMap if available.
        if(Trigger.oldMap != null){
            passedTriggerOldMap = Trigger.oldMap.clone();
            // Retrieve field names if they haven't been retrieved yet.
            if(objFieldNames == null)
                objFieldNames = LogX.getFieldNames(passedTriggerOldMap.values()[0].getSObjectType());
        }

        // Iterate through each metadata record to build a list/map of exclusions and exemptions.
        for(TriggerSetting__mdt ts : tss.values()){
            // Only proceed if the metadata's DeveloperName matches the current triggerName.
            if(ts != null && ts.DeveloperName.toUpperCase().contains(triggerName.toUpperCase())){

                // Handle AFTER event exclusions (DisableAfter__c).
                if(ts.DisableAfter__c){
                    // Check if specific operations are disabled or if all "after" events are disabled.
                    if(ts.DisableInsert__c || ts.DisableUpdate__c || ts.DisableDelete__c){
                        if(ts.DisableInsert__c)
                            exclusionList.add('AFTER_INSERT');
                        if(ts.DisableUpdate__c)
                            exclusionList.add('AFTER_UPDATE');
                        if(ts.DisableDelete__c)
                            exclusionList.add('AFTER_DELETE');
                    } else {
                        // If no specific operation flags are set, disable all after events.
                        exclusionList.add('AFTER_INSERT');
                        exclusionList.add('AFTER_UPDATE');
                        exclusionList.add('AFTER_DELETE');
                    }
                }

                // Handle BEFORE event exclusions (DisableBefore__c).
                if(ts.DisableBefore__c){
                    // Check if specific operations are disabled or if all "before" events are disabled.
                    if(ts.DisableInsert__c || ts.DisableUpdate__c || ts.DisableDelete__c){
                        if(ts.DisableInsert__c)
                            exclusionList.add('BEFORE_INSERT');
                        if(ts.DisableUpdate__c)
                            exclusionList.add('BEFORE_UPDATE');
                        if(ts.DisableDelete__c)
                            exclusionList.add('BEFORE_DELETE');
                    } else {
                        // If no specific operation flags are set, disable all before events.
                        exclusionList.add('BEFORE_INSERT');
                        exclusionList.add('BEFORE_UPDATE');
                        exclusionList.add('BEFORE_DELETE');
                    }
                }

                // Handle undelete event exclusions.
                if(ts.DisableUnDelete__c){
                    exclusionList.add('AFTER_UNDELETE');
                }

                // If a DisableUserName__c is specified, store it in the exclusion list (as uppercase).
                if(String.isNotBlank(ts.DisableUserName__c)){
                    exclusionList.add(ts.DisableUserName__c.toUpperCase());
                } else {
                    // Otherwise, if we have an ExemptUserName__c, store it in a variable for later check.
                    if(String.isNotBlank(ts.ExemptUserName__c)){
                        exemptUser = ts.ExemptUserName__c.toUpperCase();
                    }
                }

                // Check if there is a field-based exclusion (FieldApiName__c/FieldValue__c).
                // Also confirm the field exists in the SObject by checking objFieldNames.
                if(String.isNotBlank(ts.FieldApiName__c) 
                   && String.isNotBlank(ts.FieldValue__c) 
                   && objFieldNames.contains(ts.FieldApiName__c)){

                    // Ensure a set exists for this field, then add the excluded value.
                    if(!exclusionFieldValueMap.containsKey(ts.FieldApiName__c)){
                        exclusionFieldValueMap.put(ts.FieldApiName__c, new Set<String>());
                    }
                    exclusionFieldValueMap.get(ts.FieldApiName__c).add(ts.FieldValue__c);
                }
            }
        }

        // Now that we've constructed the lists/maps of exclusions, apply them if needed.
        // Check if the current trigger event is in the exclusion list (e.g. BEFORE_INSERT, AFTER_UPDATE).
        if(exclusionList.contains(Trigger.operationType?.toString())){

            // If the current user's username is also in the exclusion list, exit immediately.
            if(exclusionList.contains(UserInfo.getUserName().toUpperCase())){
                return; // This user is excluded entirely.
            }

            // If there is an exempt user specified and it matches the current user, do nothing more.
            // (Meaning the user is exempt from the exclusion and the code continues to run.)
            if(exemptUser != null && exemptUser.equalsIgnoreCase(UserInfo.getUserName())){
                return;
            }

            // If we have field-based exclusions, we need to remove records that match those exclusions.
            if(exclusionFieldValueMap == null){
                // No record-level exclusions, so we simply exit.
                return;
            } else {
                // Remove any matching records from the new/old lists/maps:
                
                // 1. Remove from passedTriggerNew
                if(passedTriggerNew != null){
                    for(Integer i = (passedTriggerNew.size() - 1); i >= 0; i--){
                        SObject s = passedTriggerNew[i];
                        for(String fieldName : exclusionFieldValueMap.keySet()){
                            // If the record's field value is in the set of excluded values, remove it.
                            if(exclusionFieldValueMap.get(fieldName).contains(String.valueOf(s.get(fieldName)))){
                                passedTriggerNew.remove(i);
                            }
                        }
                    }
                }

                // 2. Remove from passedTriggerNewMap
                if(passedTriggerNewMap != null){
                    for(Id rId : passedTriggerNewMap.keySet()){
                        SObject s = passedTriggerNewMap.get(rId);
                        for(String fieldName : exclusionFieldValueMap.keySet()){
                            if(exclusionFieldValueMap.get(fieldName).contains(String.valueOf(s.get(fieldName)))){
                                passedTriggerNewMap.remove(rId);
                            }
                        }
                    }
                }

                // 3. Remove from passedTriggerOldMap
                if(passedTriggerOldMap != null){
                    for(Id rId : passedTriggerOldMap.keySet()){
                        SObject s = passedTriggerOldMap.get(rId);
                        for(String fieldName : exclusionFieldValueMap.keySet()){
                            if(exclusionFieldValueMap.get(fieldName).contains(String.valueOf(s.get(fieldName)))){
                                passedTriggerOldMap.remove(rId);
                            }
                        }
                    }
                }
            }
        }

        // Finally, call the appropriate handler method based on the current trigger operation type.
        switch on Trigger.operationType {
            when BEFORE_INSERT {
                // Check if any records remain
                if(passedTriggerNew.size() > 0)
                    handler.beforeInsert(passedTriggerNew);
            }
            when BEFORE_UPDATE {
                // Check if any records remain
                if(passedTriggerNewMap.size() > 0)
                    handler.beforeUpdate(passedTriggerNewMap, passedTriggerOldMap);
            }
            when BEFORE_DELETE {
                // Check if any records remain
                if(passedTriggerOldMap.size() > 0)
                handler.beforeDelete(passedTriggerOldMap);
            }
            when AFTER_INSERT {
                // Check if any records remain
                if(passedTriggerNewMap.size() > 0)
                    handler.afterInsert(passedTriggerNewMap);
            }
            when AFTER_UPDATE {
                // Check if any records remain
                if(passedTriggerNewMap.size() > 0)
                    handler.afterUpdate(passedTriggerNewMap, passedTriggerOldMap);
            }
            when AFTER_DELETE {
                // Check if any records remain
                if(passedTriggerOldMap.size() > 0)
                    handler.afterDelete(passedTriggerOldMap);
            }
            when AFTER_UNDELETE {
                // Check if any records remain
                if(passedTriggerNewMap.size() > 0)
                    handler.afterUnDelete(passedTriggerNewMap);
            }
        }
    }
}