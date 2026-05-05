@IsTest
private class MappingRuleExecutorTest {

    @TestSetup
    static void makeData() {
        Source_System__c ss = new Source_System__c(Name = 'Test System', Code__c = 'TEST_EXEC', Source_Code__c = 'TEST_EXEC', Transformer_Class__c = 'WideOrbitTransformer');
        insert ss;

        List<Mapping_Rule__c> rules = new List<Mapping_Rule__c>{
            new Mapping_Rule__c(
                Name            = 'MAP_ADVERTISER',
                Source_System__c = ss.Id,
                Rule_Type__c    = 'Map',
                Field_Name__c   = 'Raw_Advertiser_Name__c',
                Raw_Value__c    = 'Coca Cola',
                Mapped_Value__c = 'Coca-Cola Company',
                Is_Active__c    = true,
                Sort_Order__c   = 1
            ),
            new Mapping_Rule__c(
                Name            = 'MAP_OUTLET',
                Source_System__c = ss.Id,
                Rule_Type__c    = 'Map',
                Field_Name__c   = 'Outlet_Code__c',
                Raw_Value__c    = 'KVEA',
                Mapped_Value__c = 'KVEA-TV',
                Is_Active__c    = true,
                Sort_Order__c   = 2
            ),
            new Mapping_Rule__c(
                Name            = 'EXCLUDE_TEST_ADV',
                Source_System__c = ss.Id,
                Rule_Type__c    = 'Exclude',
                Field_Name__c   = 'Raw_Advertiser_Name__c',
                Raw_Value__c    = 'TEST_ADVERTISER',
                Is_Active__c    = true,
                Sort_Order__c   = 3
            ),
            new Mapping_Rule__c(
                Name            = 'INACTIVE_RULE',
                Source_System__c = ss.Id,
                Rule_Type__c    = 'Map',
                Field_Name__c   = 'Raw_Advertiser_Name__c',
                Raw_Value__c    = 'ShouldNotMatch',
                Mapped_Value__c = 'SHOULD_NOT_APPEAR',
                Is_Active__c    = false,
                Sort_Order__c   = 4
            )
        };
        insert rules;
    }

    static Id getSourceSystemId() {
        return [SELECT Id FROM Source_System__c WHERE Code__c = 'TEST_EXEC' LIMIT 1].Id;
    }

    // ── Map rule tests ────────────────────────────────────────────────────

    @IsTest
    static void mapRule_matchingAdvertiser_nameNormalized() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Status__c = 'Pending',
            Raw_Advertiser_Name__c = 'Coca Cola'
        );

        Test.startTest();
        new MappingRuleExecutor(getSourceSystemId()).apply(new List<Inbound_Staging__c>{ row });
        Test.stopTest();

        System.assertEquals('Coca-Cola Company', row.Raw_Advertiser_Name__c,
            'Map rule should normalize the advertiser name');
        System.assertEquals('Pending', row.Status__c);
    }

    @IsTest
    static void mapRule_caseInsensitiveMatch_nameNormalized() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Status__c = 'Pending',
            Raw_Advertiser_Name__c = 'coca cola'
        );

        Test.startTest();
        new MappingRuleExecutor(getSourceSystemId()).apply(new List<Inbound_Staging__c>{ row });
        Test.stopTest();

        System.assertEquals('Coca-Cola Company', row.Raw_Advertiser_Name__c,
            'Map rule should match case-insensitively');
    }

    @IsTest
    static void mapRule_outletCode_codeNormalized() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Status__c = 'Pending',
            Outlet_Code__c = 'KVEA'
        );

        Test.startTest();
        new MappingRuleExecutor(getSourceSystemId()).apply(new List<Inbound_Staging__c>{ row });
        Test.stopTest();

        System.assertEquals('KVEA-TV', row.Outlet_Code__c);
    }

    @IsTest
    static void mapRule_noMatch_fieldUnchanged() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Status__c = 'Pending',
            Raw_Advertiser_Name__c = 'Unknown Brand'
        );

        Test.startTest();
        new MappingRuleExecutor(getSourceSystemId()).apply(new List<Inbound_Staging__c>{ row });
        Test.stopTest();

        System.assertEquals('Unknown Brand', row.Raw_Advertiser_Name__c,
            'No matching rule — field must be unchanged');
    }

    @IsTest
    static void inactiveRule_notApplied() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Status__c = 'Pending',
            Raw_Advertiser_Name__c = 'ShouldNotMatch'
        );

        Test.startTest();
        new MappingRuleExecutor(getSourceSystemId()).apply(new List<Inbound_Staging__c>{ row });
        Test.stopTest();

        System.assertEquals('ShouldNotMatch', row.Raw_Advertiser_Name__c,
            'Inactive rule must never fire');
    }

    // ── Exclude rule tests ────────────────────────────────────────────────

    @IsTest
    static void excludeRule_matchingValue_rowMarkedExcluded() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Status__c = 'Pending',
            Raw_Advertiser_Name__c = 'TEST_ADVERTISER'
        );

        Test.startTest();
        new MappingRuleExecutor(getSourceSystemId()).apply(new List<Inbound_Staging__c>{ row });
        Test.stopTest();

        System.assertEquals('Excluded', row.Status__c);
        System.assertEquals('EXCLUDE_TEST_ADV', row.Excluding_Rule__c,
            'Excluding_Rule__c should be set to the Mapping_Rule__c Name');
    }

    @IsTest
    static void excludeRule_alreadyExcluded_skipped() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Status__c = 'Excluded',
            Raw_Advertiser_Name__c = 'Coca Cola',
            Excluding_Rule__c = 'PRIOR_EXCLUSION'
        );

        Test.startTest();
        new MappingRuleExecutor(getSourceSystemId()).apply(new List<Inbound_Staging__c>{ row });
        Test.stopTest();

        // Already-excluded rows must not be modified
        System.assertEquals('Excluded', row.Status__c);
        System.assertEquals('PRIOR_EXCLUSION', row.Excluding_Rule__c);
        System.assertEquals('Coca Cola', row.Raw_Advertiser_Name__c,
            'Map rule must not fire on an already-excluded row');
    }

    // ── Edge cases ────────────────────────────────────────────────────────

    @IsTest
    static void errorRow_notModified() {
        Inbound_Staging__c row = new Inbound_Staging__c(
            Status__c = 'Error',
            Raw_Advertiser_Name__c = 'Coca Cola'
        );

        Test.startTest();
        new MappingRuleExecutor(getSourceSystemId()).apply(new List<Inbound_Staging__c>{ row });
        Test.stopTest();

        System.assertEquals('Coca Cola', row.Raw_Advertiser_Name__c,
            'Error rows must never be modified');
    }

    @IsTest
    static void noRules_rowsPassThrough() {
        Source_System__c empty = new Source_System__c(Name = 'No Rules SS', Code__c = 'NORULES_EXEC', Source_Code__c = 'NORULES_EXEC', Transformer_Class__c = 'WideOrbitTransformer');
        insert empty;

        Inbound_Staging__c row = new Inbound_Staging__c(
            Status__c = 'Pending',
            Raw_Advertiser_Name__c = 'Any Brand'
        );

        Test.startTest();
        new MappingRuleExecutor(empty.Id).apply(new List<Inbound_Staging__c>{ row });
        Test.stopTest();

        System.assertEquals('Pending', row.Status__c);
        System.assertEquals('Any Brand', row.Raw_Advertiser_Name__c);
    }

    @IsTest
    static void emptyRowList_noException() {
        Test.startTest();
        new MappingRuleExecutor(getSourceSystemId()).apply(new List<Inbound_Staging__c>());
        Test.stopTest();
        System.assert(true, 'Empty list must not throw');
    }
}
