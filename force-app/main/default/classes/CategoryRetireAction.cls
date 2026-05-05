public with sharing class CategoryRetireAction {

    public class RetireRequest {
        @InvocableVariable(label='Category ID' required=true)
        public Id categoryId;

        @InvocableVariable(label='Successor Category ID')
        public Id successorCategoryId;
    }

    public class RetireResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;

        @InvocableVariable(label='Moved Account Category Count')
        public Integer movedAccountCategoryCount;

        @InvocableVariable(label='Moved Child Category Count')
        public Integer movedChildCategoryCount;
    }

    @InvocableMethod(
        label='Retire Category With Successor'
        description='Retires a Category, migrating Account_Category__c junctions and child categories to a successor.'
    )
    public static List<RetireResult> retireCategory(List<RetireRequest> requests) {
        List<RetireResult> results = new List<RetireResult>();

        for (RetireRequest req : requests) {
            RetireResult result = new RetireResult();
            result.success = false;
            result.movedAccountCategoryCount = 0;
            result.movedChildCategoryCount = 0;

            try {
                Category__c retiring = [
                    SELECT Id, Name, Is_Active__c, Successor_Category__c
                    FROM Category__c
                    WHERE Id = :req.categoryId
                    FOR UPDATE
                ];

                Id successorId = req.successorCategoryId != null
                    ? req.successorCategoryId
                    : retiring.Successor_Category__c;

                // Migrate Account_Category__c junctions
                List<Account_Category__c> junctions = [
                    SELECT Id, Category__c
                    FROM Account_Category__c
                    WHERE Category__c = :req.categoryId
                ];
                if (!junctions.isEmpty()) {
                    if (successorId == null) {
                        throw new AuraHandledException(
                            'A successor category is required — this category has ' +
                            junctions.size() + ' account assignment(s).'
                        );
                    }
                    for (Account_Category__c j : junctions) {
                        j.Category__c = successorId;
                    }
                    update junctions;
                    result.movedAccountCategoryCount = junctions.size();
                }

                // Migrate child categories to the successor (or detach if no successor)
                List<Category__c> children = [
                    SELECT Id, Parent_Category__c
                    FROM Category__c
                    WHERE Parent_Category__c = :req.categoryId
                ];
                if (!children.isEmpty()) {
                    for (Category__c child : children) {
                        child.Parent_Category__c = successorId;
                    }
                    update children;
                    result.movedChildCategoryCount = children.size();
                }

                // Retire
                retiring.Is_Active__c = false;
                if (successorId != null) {
                    retiring.Successor_Category__c = successorId;
                }
                update retiring;

                result.success = true;
                result.message = 'Category retired. '
                    + result.movedAccountCategoryCount + ' account assignment(s) and '
                    + result.movedChildCategoryCount + ' sub-category(s) moved to successor.';

            } catch (Exception e) {
                result.message = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }
}
