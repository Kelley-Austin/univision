public with sharing class CategoryService {

    @AuraEnabled(cacheable=true)
    public static List<Category__c> getCategoryTree() {
        return [
            SELECT Id, Name, Parent_Category__c, Parent_Category__r.Name,
                   Is_Active__c, Sort_Order__c, Description__c,
                   Successor_Category__c, Level__c, Full_Path__c
            FROM Category__c
            ORDER BY Sort_Order__c NULLS LAST, Name
            LIMIT 2000
        ];
    }

    @AuraEnabled
    public static void reparentCategory(Id categoryId, Id newParentId) {
        if (categoryId == null) {
            throw new AuraHandledException('Category ID is required.');
        }
        if (categoryId == newParentId) {
            throw new AuraHandledException('A category cannot be its own parent.');
        }
        if (newParentId != null && wouldCreateCycle(categoryId, newParentId)) {
            throw new AuraHandledException('Cannot move a category to one of its own descendants.');
        }

        Category__c cat = new Category__c(Id = categoryId, Parent_Category__c = newParentId);
        update cat;
    }

    @AuraEnabled(cacheable=true)
    public static List<Category__c> getActiveCategories() {
        return [
            SELECT Id, Name, Parent_Category__r.Name, Full_Path__c
            FROM Category__c
            WHERE Is_Active__c = true
            ORDER BY Full_Path__c NULLS LAST, Name
            LIMIT 1000
        ];
    }

    // Returns true if making newParentId the parent of categoryId would create a cycle.
    // Walks up from newParentId through the parent chain; if it reaches categoryId, it's a cycle.
    private static Boolean wouldCreateCycle(Id categoryId, Id newParentId) {
        Map<Id, Id> parentMap = new Map<Id, Id>();
        for (Category__c cat : [
            SELECT Id, Parent_Category__c FROM Category__c
            LIMIT 2000
        ]) {
            if (cat.Parent_Category__c != null) {
                parentMap.put(cat.Id, cat.Parent_Category__c);
            }
        }

        Set<Id> visited = new Set<Id>();
        Id currentId = newParentId;
        while (currentId != null && !visited.contains(currentId)) {
            if (currentId == categoryId) return true;
            visited.add(currentId);
            currentId = parentMap.get(currentId);
        }
        return false;
    }
}
