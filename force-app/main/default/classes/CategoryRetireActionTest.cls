@IsTest
private class CategoryRetireActionTest {

    @TestSetup
    static void setup() {
        Category__c parent = new Category__c(Name = 'Parent', Is_Active__c = true);
        insert parent;

        Category__c retiring = new Category__c(Name = 'Retiring', Is_Active__c = true, Parent_Category__c = parent.Id);
        insert retiring;

        Category__c successor = new Category__c(Name = 'Successor', Is_Active__c = true, Parent_Category__c = parent.Id);
        insert successor;

        Category__c child = new Category__c(Name = 'Child of Retiring', Is_Active__c = true, Parent_Category__c = retiring.Id);
        insert child;

        // Get an Account with no specific record type for the junction (avoid RT dependency in this test)
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        Account_Category__c junc = new Account_Category__c(
            Account__c = acct.Id,
            Category__c = retiring.Id
        );
        insert junc;
    }

    @IsTest
    static void retire_withSuccessor_migratesRelationships() {
        Category__c retiring = [SELECT Id FROM Category__c WHERE Name = 'Retiring' LIMIT 1];
        Category__c successor = [SELECT Id FROM Category__c WHERE Name = 'Successor' LIMIT 1];

        CategoryRetireAction.RetireRequest req = new CategoryRetireAction.RetireRequest();
        req.categoryId = retiring.Id;
        req.successorCategoryId = successor.Id;

        Test.startTest();
        List<CategoryRetireAction.RetireResult> results =
            CategoryRetireAction.retireCategory(new List<CategoryRetireAction.RetireRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].success, 'Retire should succeed: ' + results[0].message);
        System.assertEquals(1, results[0].movedAccountCategoryCount, 'One Account_Category__c should be moved');
        System.assertEquals(1, results[0].movedChildCategoryCount, 'One child category should be moved');

        Category__c retired = [SELECT Is_Active__c, Successor_Category__c FROM Category__c WHERE Id = :retiring.Id];
        System.assert(!retired.Is_Active__c, 'Retiring category should be inactive');
        System.assertEquals(successor.Id, retired.Successor_Category__c, 'Successor should be set');

        // Verify junction moved
        List<Account_Category__c> junctions = [
            SELECT Category__c FROM Account_Category__c WHERE Category__c = :successor.Id
        ];
        System.assertEquals(1, junctions.size(), 'Junction should now point to successor');

        // Verify child category re-parented
        Category__c child = [SELECT Parent_Category__c FROM Category__c WHERE Name = 'Child of Retiring' LIMIT 1];
        System.assertEquals(successor.Id, child.Parent_Category__c, 'Child should be re-parented to successor');
    }

    @IsTest
    static void retire_noRelationships_succeedsWithoutSuccessor() {
        // A category with no children and no junctions can be retired without a successor
        Category__c solo = new Category__c(Name = 'Solo', Is_Active__c = true);
        insert solo;

        CategoryRetireAction.RetireRequest req = new CategoryRetireAction.RetireRequest();
        req.categoryId = solo.Id;
        req.successorCategoryId = null;

        Test.startTest();
        List<CategoryRetireAction.RetireResult> results =
            CategoryRetireAction.retireCategory(new List<CategoryRetireAction.RetireRequest>{ req });
        Test.stopTest();

        System.assert(results[0].success, 'Should succeed without successor when no relationships exist');
        Category__c updated = [SELECT Is_Active__c FROM Category__c WHERE Id = :solo.Id];
        System.assert(!updated.Is_Active__c, 'Should be inactive');
    }

    @IsTest
    static void retire_withRelationshipsNoSuccessor_fails() {
        Category__c retiring = [SELECT Id FROM Category__c WHERE Name = 'Retiring' LIMIT 1];

        CategoryRetireAction.RetireRequest req = new CategoryRetireAction.RetireRequest();
        req.categoryId = retiring.Id;
        req.successorCategoryId = null;

        Test.startTest();
        List<CategoryRetireAction.RetireResult> results =
            CategoryRetireAction.retireCategory(new List<CategoryRetireAction.RetireRequest>{ req });
        Test.stopTest();

        System.assert(!results[0].success, 'Should fail when relationships exist and no successor given');
        System.assert(results[0].message != null, 'Should return an error message');
    }

    @IsTest
    static void retire_usesStoredSuccessorWhenNoneProvided() {
        Category__c successor = [SELECT Id FROM Category__c WHERE Name = 'Successor' LIMIT 1];
        Category__c retiring = [SELECT Id FROM Category__c WHERE Name = 'Retiring' LIMIT 1];

        // Pre-set the Successor_Category__c field on the retiring record
        retiring.Successor_Category__c = successor.Id;
        update retiring;

        CategoryRetireAction.RetireRequest req = new CategoryRetireAction.RetireRequest();
        req.categoryId = retiring.Id;
        req.successorCategoryId = null; // not provided — should fall back to field value

        Test.startTest();
        List<CategoryRetireAction.RetireResult> results =
            CategoryRetireAction.retireCategory(new List<CategoryRetireAction.RetireRequest>{ req });
        Test.stopTest();

        System.assert(results[0].success, 'Should succeed using stored successor: ' + results[0].message);
    }
}
