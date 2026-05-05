@IsTest
private class MappingRuleServiceTest {

    @TestSetup
    static void setup() {
        Source_System__c ss = new Source_System__c(Name = 'WideOrbit TV', Code__c = 'WIDEORBIT_TV', Source_Code__c = 'WIDEORBIT_TV', Transformer_Class__c = 'WideOrbitTransformer', Is_Active__c = true);
        insert ss;
    }

    private static Source_System__c getSource() {
        return [SELECT Id FROM Source_System__c WHERE Code__c = 'WIDEORBIT_TV' LIMIT 1];
    }

    @IsTest
    static void getRules_returnsRulesForSourceSystem() {
        Source_System__c ss = getSource();
        Mapping_Rule__c rule = new Mapping_Rule__c(
            Name = 'Test Rule',
            Source_System__c = ss.Id,
            Rule_Type__c = 'Map',
            Field_Name__c = 'Revenue_Type__c',
            Raw_Value__c = 'OLD',
            Mapped_Value__c = 'NEW',
            Is_Active__c = true,
            Notes__c = 'Test notes'
        );
        insert rule;

        Test.startTest();
        List<Mapping_Rule__c> rules = MappingRuleService.getRules(ss.Id);
        Test.stopTest();

        System.assertEquals(1, rules.size());
        System.assertEquals('Test Rule', rules[0].Name);
    }

    @IsTest
    static void saveRule_insertsNewRule() {
        Source_System__c ss = getSource();
        Mapping_Rule__c rule = new Mapping_Rule__c(
            Name = 'New Rule',
            Source_System__c = ss.Id,
            Rule_Type__c = 'Exclude',
            Field_Name__c = 'Outlet_Code__c',
            Raw_Value__c = 'TEST',
            Is_Active__c = false,
            Notes__c = 'Test'
        );

        Test.startTest();
        MappingRuleService.saveRule(rule);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Mapping_Rule__c WHERE Name = 'New Rule']);
    }

    @IsTest
    static void dryRun_withOneExcludeRuleMatchingOneRow_wouldExcludeOne() {
        Source_System__c ss = getSource();
        Mapping_Rule__c rule = new Mapping_Rule__c(
            Name = 'Exclude TEST',
            Source_System__c = ss.Id,
            Rule_Type__c = 'Exclude',
            Field_Name__c = 'Raw_Advertiser_Name__c',
            Raw_Value__c = 'EXCLUDE_ME',
            Is_Active__c = true,
            Notes__c = 'Dry run test'
        );
        insert rule;

        Inbound_Staging__c row1 = new Inbound_Staging__c(
            Source_System__c = ss.Id,
            Raw_Advertiser_Name__c = 'EXCLUDE_ME',
            Status__c = 'Pending'
        );
        Inbound_Staging__c row2 = new Inbound_Staging__c(
            Source_System__c = ss.Id,
            Raw_Advertiser_Name__c = 'KEEP_ME',
            Status__c = 'Pending'
        );
        insert new List<Inbound_Staging__c>{ row1, row2 };

        Test.startTest();
        MappingRuleService.DryRunResult result = MappingRuleService.dryRun(ss.Id);
        Test.stopTest();

        System.assertEquals(2, result.pendingRows);
        System.assertEquals(1, result.wouldExclude);
    }

    @IsTest
    static void activateRule_togglingWorks() {
        Source_System__c ss = getSource();
        Mapping_Rule__c rule = new Mapping_Rule__c(
            Name = 'Toggle Rule',
            Source_System__c = ss.Id,
            Rule_Type__c = 'Map',
            Field_Name__c = 'Revenue_Type__c',
            Raw_Value__c = 'X',
            Mapped_Value__c = 'Y',
            Is_Active__c = true,
            Notes__c = 'Toggle test'
        );
        insert rule;

        Test.startTest();
        MappingRuleService.activateRule(rule.Id, false);
        Test.stopTest();

        Mapping_Rule__c updated = [SELECT Is_Active__c FROM Mapping_Rule__c WHERE Id = :rule.Id];
        System.assertEquals(false, updated.Is_Active__c);
    }

    @IsTest
    static void deleteRule_removesRecord() {
        Source_System__c ss = getSource();
        Mapping_Rule__c rule = new Mapping_Rule__c(
            Name = 'Delete Me',
            Source_System__c = ss.Id,
            Rule_Type__c = 'Map',
            Field_Name__c = 'Revenue_Type__c',
            Raw_Value__c = 'A',
            Mapped_Value__c = 'B',
            Is_Active__c = false,
            Notes__c = 'Delete test'
        );
        insert rule;

        Test.startTest();
        MappingRuleService.deleteRule(rule.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Mapping_Rule__c WHERE Id = :rule.Id]);
    }
}
