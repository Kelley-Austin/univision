@IsTest
private class CategoryServiceTest {

    @TestSetup
    static void setup() {
        Category__c root = new Category__c(Name = 'Root', Is_Active__c = true, Sort_Order__c = 1);
        insert root;

        Category__c child = new Category__c(
            Name = 'Child', Is_Active__c = true,
            Parent_Category__c = root.Id, Sort_Order__c = 1
        );
        insert child;

        Category__c grandchild = new Category__c(
            Name = 'Grandchild', Is_Active__c = true,
            Parent_Category__c = child.Id, Sort_Order__c = 1
        );
        insert grandchild;

        Category__c inactive = new Category__c(Name = 'Inactive', Is_Active__c = false);
        insert inactive;
    }

    @IsTest
    static void getCategoryTree_returnsAllCategories() {
        Test.startTest();
        List<Category__c> results = CategoryService.getCategoryTree();
        Test.stopTest();

        System.assertEquals(4, results.size(), 'All 4 categories (including inactive) should be returned');
    }

    @IsTest
    static void getActiveCategories_excludesInactive() {
        Test.startTest();
        List<Category__c> results = CategoryService.getActiveCategories();
        Test.stopTest();

        for (Category__c cat : results) {
            System.assert(cat.Is_Active__c, 'Only active categories should be returned');
        }
        System.assertEquals(3, results.size(), 'Only the 3 active categories should be returned');
    }

    @IsTest
    static void reparentCategory_happyPath() {
        Category__c root = [SELECT Id FROM Category__c WHERE Name = 'Root' LIMIT 1];
        Category__c grandchild = [SELECT Id FROM Category__c WHERE Name = 'Grandchild' LIMIT 1];

        Test.startTest();
        CategoryService.reparentCategory(grandchild.Id, root.Id);
        Test.stopTest();

        Category__c updated = [SELECT Parent_Category__c FROM Category__c WHERE Id = :grandchild.Id];
        System.assertEquals(root.Id, updated.Parent_Category__c, 'Grandchild should now report directly to Root');
    }

    @IsTest
    static void reparentCategory_nullParentDetachesFromTree() {
        Category__c child = [SELECT Id FROM Category__c WHERE Name = 'Child' LIMIT 1];

        Test.startTest();
        CategoryService.reparentCategory(child.Id, null);
        Test.stopTest();

        Category__c updated = [SELECT Parent_Category__c FROM Category__c WHERE Id = :child.Id];
        System.assertEquals(null, updated.Parent_Category__c, 'Child should be detached from the tree');
    }

    @IsTest
    static void reparentCategory_selfParentThrows() {
        Category__c root = [SELECT Id FROM Category__c WHERE Name = 'Root' LIMIT 1];

        Test.startTest();
        try {
            CategoryService.reparentCategory(root.Id, root.Id);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('own parent'), 'Error should mention own parent');
        }
        Test.stopTest();
    }

    @IsTest
    static void reparentCategory_cyclePrevented() {
        Category__c root = [SELECT Id FROM Category__c WHERE Name = 'Root' LIMIT 1];
        Category__c child = [SELECT Id FROM Category__c WHERE Name = 'Child' LIMIT 1];

        // Attempting to make Root a child of Child would create a cycle (Root → Child → Root)
        Test.startTest();
        try {
            CategoryService.reparentCategory(root.Id, child.Id);
            System.assert(false, 'Expected AuraHandledException for cycle');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('descendant'), 'Error should mention descendant');
        }
        Test.stopTest();
    }

    @IsTest
    static void reparentCategory_nullIdThrows() {
        Test.startTest();
        try {
            CategoryService.reparentCategory(null, null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required');
        }
        Test.stopTest();
    }
}
