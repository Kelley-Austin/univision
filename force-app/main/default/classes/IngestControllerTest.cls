@IsTest
private class IngestControllerTest {

    @TestSetup
    static void setup() {
        TransformerTestHelper.makeSource('STRATA', 'StrataTransformer', 'UTF-8');
        TransformerTestHelper.makeSource('COXREPS', 'CoxRepsTransformer', 'UTF-8');
    }

    private static Source_System__c getStrata() {
        return [SELECT Id FROM Source_System__c WHERE Source_Code__c = 'STRATA' LIMIT 1];
    }

    private static Id insertCsv(String csv, String filename) {
        ContentVersion cv = new ContentVersion(
            Title        = filename,
            PathOnClient = filename,
            VersionData  = Blob.valueOf(csv),
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    @IsTest
    static void getActiveSources_returnsOnlyActiveSystems() {
        // Deactivate CoxReps
        Source_System__c cr = [SELECT Id FROM Source_System__c WHERE Source_Code__c = 'COXREPS' LIMIT 1];
        cr.Is_Active__c = false;
        update cr;

        Test.startTest();
        List<Source_System__c> results = IngestController.getActiveSources();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Only active sources returned');
        System.assertEquals('STRATA', results[0].Source_Code__c);
    }

    @IsTest
    static void processUpload_insertsRows() {
        Source_System__c ss = getStrata();
        String csv = 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
                   + 'ctrl-guid-111-222-333-4445567,Ctrl Corp,Agency,KTVW,Local,7500,AE,2026-03\n';
        Id cdId = insertCsv(csv, 'ctrl_test.csv');

        Test.startTest();
        IngestService.IngestResult result = IngestController.processUpload(cdId, ss.Id);
        Test.stopTest();

        System.assertEquals(1, result.totalRows);
        System.assertEquals(1, [SELECT COUNT() FROM Inbound_Staging__c]);
    }

    @IsTest
    static void getMappingRules_returnsActiveRulesInOrder() {
        Source_System__c ss = getStrata();
        insert new List<Mapping_Rule__c>{
            new Mapping_Rule__c(Name = 'Rule A', Source_System__c = ss.Id,
                Source_Field__c = 'advertiser_name', Target_Field__c = 'Advertiser_Name__c',
                Sort_Order__c = 2, Is_Active__c = true),
            new Mapping_Rule__c(Name = 'Rule B', Source_System__c = ss.Id,
                Source_Field__c = 'net_revenue', Target_Field__c = 'Revenue_Amount__c',
                Sort_Order__c = 1, Is_Active__c = true),
            new Mapping_Rule__c(Name = 'Rule C (inactive)', Source_System__c = ss.Id,
                Source_Field__c = 'foo', Target_Field__c = 'bar',
                Sort_Order__c = 3, Is_Active__c = false)
        };

        Test.startTest();
        List<Mapping_Rule__c> rules = IngestController.getMappingRules(ss.Id);
        Test.stopTest();

        System.assertEquals(2, rules.size(), 'Inactive rule excluded');
        System.assertEquals('Rule B', rules[0].Name, 'Sorted by Sort_Order__c ASC');
    }

    @IsTest
    static void saveMappingRule_upserts() {
        Source_System__c ss = getStrata();
        Mapping_Rule__c rule = new Mapping_Rule__c(
            Name = 'New Rule', Source_System__c = ss.Id,
            Source_Field__c = 'ae_code', Target_Field__c = 'AE_Code__c',
            Is_Active__c = true
        );

        Test.startTest();
        IngestController.saveMappingRule(rule);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Mapping_Rule__c WHERE Source_System__c = :ss.Id]);
    }

    @IsTest
    static void deleteMappingRule_removesRecord() {
        Source_System__c ss = getStrata();
        Mapping_Rule__c rule = new Mapping_Rule__c(
            Name = 'To Delete', Source_System__c = ss.Id,
            Source_Field__c = 'x', Target_Field__c = 'y', Is_Active__c = true
        );
        insert rule;

        Test.startTest();
        IngestController.deleteMappingRule(rule.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Mapping_Rule__c WHERE Id = :rule.Id]);
    }

    @IsTest
    static void dryRun_doesNotPersist() {
        Source_System__c ss = getStrata();
        String csv = 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
                   + 'dry-guid-111-222-333-4445567x,Dry Corp,Agency,KTVW,Local,2000,AE,2026-03\n';
        Id cdId = insertCsv(csv, 'dry_test.csv');

        Test.startTest();
        IngestService.IngestResult result = IngestController.dryRun(cdId, ss.Id);
        Test.stopTest();

        System.assert(result.dryRun);
        System.assertEquals(0, [SELECT COUNT() FROM Inbound_Staging__c], 'Dry run must not persist');
    }

    @IsTest
    static void getBatchStats_aggregatesBySourceAndStatus() {
        Source_System__c ss = getStrata();
        insert new List<Inbound_Staging__c>{
            new Inbound_Staging__c(Source_System__c = ss.Id, Status__c = 'Pending',
                External_Key__c = 'stat-key-001'),
            new Inbound_Staging__c(Source_System__c = ss.Id, Status__c = 'Excluded',
                External_Key__c = 'stat-key-002', Excluding_Rule__c = 'NULL_GUID')
        };

        Test.startTest();
        List<IngestController.BatchStat> stats = IngestController.getBatchStats();
        Test.stopTest();

        System.assert(!stats.isEmpty(), 'Stats should return at least one entry');
    }

    @IsTest
    static void launchBatch_returnsJobId() {
        Source_System__c ss = getStrata();

        Test.startTest();
        Id jobId = IngestController.launchBatch(ss.Id);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Batch job Id should be returned');
    }
}
