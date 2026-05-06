@isTest
public class TriggerDispatcherTest {

    @testSetup
    static void setupTestData() {

        // Insert test records for the trigger
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'Test Account ' + i));
        }
        insert accounts;
    }

    @isTest
    static void testBeforeInsertHandler() {
        Test.startTest();
        
        List<Account> newAccounts = new List<Account>{
            new Account(Name = 'Before Insert Test 1'),
            new Account(Name = 'Before Insert Test 2')
        };

        TestTriggerHandler handler = new TestTriggerHandler();
        TriggerDispatcher.run(handler, 'TestTrigger');

        Test.stopTest();

    }

    @isTest
    static void testAfterInsertHandler() {
        Test.startTest();
        
        List<Account> newAccounts = new List<Account>{
            new Account(Name = 'After Insert Test 1'),
            new Account(Name = 'After Insert Test 2')
        };
        insert newAccounts;

        Test.stopTest();

        TestTriggerHandler handler = new TestTriggerHandler();
        TriggerDispatcher.run(handler, 'TestTrigger');

    }

    @isTest
    static void testBeforeUpdateHandler() {
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 2];
        for (Account acc : accounts) {
            acc.Name = 'Updated Account';
        }

        Test.startTest();
        update accounts;
        Test.stopTest();

        TestTriggerHandler handler = new TestTriggerHandler();
        TriggerDispatcher.run(handler, 'TestTrigger');

    }

    @isTest
    static void testAfterUpdateHandler() {
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 2];
        for (Account acc : accounts) {
            acc.Name = 'Updated Account After';
        }

        Test.startTest();
        update accounts;
        Test.stopTest();

        TestTriggerHandler handler = new TestTriggerHandler();
        TriggerDispatcher.run(handler, 'TestTrigger');

    }

    @isTest
    static void testBeforeDeleteHandler() {
        List<Account> accounts = [SELECT Id FROM Account LIMIT 2];

        Test.startTest();
        delete accounts;
        Test.stopTest();

        TestTriggerHandler handler = new TestTriggerHandler();
        TriggerDispatcher.run(handler, 'TestTrigger');

    }

    @isTest
    static void testAfterDeleteHandler() {
        List<Account> accounts = [SELECT Id FROM Account LIMIT 2];

        Test.startTest();
        delete accounts;
        Test.stopTest();

        TestTriggerHandler handler = new TestTriggerHandler();
        TriggerDispatcher.run(handler, 'TestTrigger');

    }

    @isTest
    static void testAfterUnDeleteHandler() {
        List<Account> accounts = [SELECT Id FROM Account WHERE IsDeleted = true LIMIT 2];

        Test.startTest();
        undelete accounts;
        Test.stopTest();

        TestTriggerHandler handler = new TestTriggerHandler();
        TriggerDispatcher.run(handler, 'TestTrigger');

    }

    /**
     * Custom test handler class extending TriggerHandler for validation.
     */
    private class TestTriggerHandler extends TriggerHandler {
        public Integer beforeInsertCount = 0;
        public Integer afterInsertCount = 0;
        public Integer beforeUpdateCount = 0;
        public Integer afterUpdateCount = 0;
        public Integer beforeDeleteCount = 0;
        public Integer afterDeleteCount = 0;
        public Integer afterUnDeleteCount = 0;

        public override void beforeInsert(List<SObject> newRecords) {
            beforeInsertCount = newRecords.size();
        }

        public override void afterInsert(Map<Id, SObject> newRecordsMap) {
            afterInsertCount = newRecordsMap.size();
        }

        public override void beforeUpdate(Map<Id, SObject> newRecordsMap, Map<Id, SObject> oldRecordsMap) {
            beforeUpdateCount = newRecordsMap.size();
        }

        public override void afterUpdate(Map<Id, SObject> newRecordsMap, Map<Id, SObject> oldRecordsMap) {
            afterUpdateCount = newRecordsMap.size();
        }

        public override void beforeDelete(Map<Id, SObject> oldRecordsMap) {
            beforeDeleteCount = oldRecordsMap.size();
        }

        public override void afterDelete(Map<Id, SObject> oldRecordsMap) {
            afterDeleteCount = oldRecordsMap.size();
        }

        public override void afterUnDelete(Map<Id, SObject> newRecordsMap) {
            afterUnDeleteCount = newRecordsMap.size();
        }
    }
}