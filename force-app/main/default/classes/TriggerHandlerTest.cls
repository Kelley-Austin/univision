@isTest
public class TriggerHandlerTest {

    @isTest
    static void testBeforeInsert() {
        TriggerHandler th = new TriggerHandler();
        th.beforeInsert(new List<SObject>());
    }
    
    @isTest
    static void testAfterInsert() {
        TriggerHandler th = new TriggerHandler();
        th.afterInsert(new Map<Id, SObject>());
    }
    
    @isTest
    static void testBeforeUpdate() {
        TriggerHandler th = new TriggerHandler();
        th.beforeUpdate(new Map<Id, SObject>(), new Map<Id, sObject>());
    }
    
    @isTest
    static void testAfterUpdate() {
        TriggerHandler th = new TriggerHandler();
        th.afterUpdate(null, null);
    }
    
    @isTest
    static void testBeforeDelete() {
        TriggerHandler th = new TriggerHandler();
        th.beforeInsert(null);
    }
    
    @isTest
    static void testafterDelete() {
        TriggerHandler th = new TriggerHandler();
        th.afterDelete(null);
    }
    
    @isTest
    static void testafterUnDelete() {
        TriggerHandler th = new TriggerHandler();
        th.afterUnDelete(null);
    }
    

   
}