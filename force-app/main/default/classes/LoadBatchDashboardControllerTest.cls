@IsTest
private class LoadBatchDashboardControllerTest {

    @TestSetup
    static void setup() {
        Source_System__c ss = new Source_System__c(
            Name = 'WideOrbit TV', Code__c = 'WIDEORBIT_TV',
            Source_Code__c = 'WIDEORBIT_TV', Is_Active__c = true
        );
        insert ss;

        List<Load_Batch__c> batches = new List<Load_Batch__c>{
            new Load_Batch__c(
                Source_System__c = ss.Id,
                File_Name__c = 'wideorbit_2025_01.tsv',
                Status__c = 'Failed',
                Row_Count__c = 100,
                Error_Count__c = 15,
                Processed_At__c = Datetime.now().addHours(-2)
            ),
            new Load_Batch__c(
                Source_System__c = ss.Id,
                File_Name__c = 'wideorbit_2025_02.tsv',
                Status__c = 'Complete',
                Row_Count__c = 200,
                Error_Count__c = 0,
                Processed_At__c = Datetime.now().addHours(-1)
            ),
            new Load_Batch__c(
                Source_System__c = ss.Id,
                File_Name__c = 'wideorbit_2025_03.tsv',
                Status__c = 'Complete',
                Row_Count__c = 150,
                Error_Count__c = 0,
                Processed_At__c = Datetime.now()
            )
        };
        insert batches;
    }

    private static Id getSourceSystemId() {
        return [SELECT Id FROM Source_System__c WHERE Code__c = 'WIDEORBIT_TV' LIMIT 1].Id;
    }

    @IsTest
    static void getRecentBatches_returnsAllBatches() {
        Id ssId = getSourceSystemId();

        Test.startTest();
        List<Load_Batch__c> batches = LoadBatchDashboardController.getRecentBatches(ssId, 10);
        Test.stopTest();

        System.assertEquals(3, batches.size());
    }

    @IsTest
    static void getRecentBatches_limitRespected() {
        Id ssId = getSourceSystemId();

        Test.startTest();
        List<Load_Batch__c> batches = LoadBatchDashboardController.getRecentBatches(ssId, 2);
        Test.stopTest();

        System.assertEquals(2, batches.size());
    }

    @IsTest
    static void getRecentBatches_nullLimit_defaultsTo20() {
        Id ssId = getSourceSystemId();

        Test.startTest();
        List<Load_Batch__c> batches = LoadBatchDashboardController.getRecentBatches(ssId, null);
        Test.stopTest();

        System.assertEquals(3, batches.size(), 'Null limit should default to 20');
    }

    @IsTest
    static void getRecentBatches_zeroLimit_defaultsTo20() {
        Id ssId = getSourceSystemId();

        Test.startTest();
        List<Load_Batch__c> batches = LoadBatchDashboardController.getRecentBatches(ssId, 0);
        Test.stopTest();

        System.assertEquals(3, batches.size(), 'Zero limit should default to 20');
    }

    @IsTest
    static void getSummary_aggregatesRowsAndErrors() {
        Id ssId = getSourceSystemId();

        Test.startTest();
        LoadBatchDashboardController.BatchSummary summary = LoadBatchDashboardController.getSummary(ssId);
        Test.stopTest();

        System.assertEquals(3, summary.batchCount);
        System.assertEquals(450, summary.totalRowsToday, '100 + 200 + 150 = 450');
        System.assertEquals(15, summary.totalErrorsToday, 'Only the Failed batch has errors');
    }

    @IsTest
    static void getSummary_differentSourceSystem_returnsZeroes() {
        Source_System__c other = new Source_System__c(
            Name = 'Strata', Code__c = 'STRATA',
            Source_Code__c = 'STRATA', Is_Active__c = true
        );
        insert other;

        Test.startTest();
        LoadBatchDashboardController.BatchSummary summary = LoadBatchDashboardController.getSummary(other.Id);
        Test.stopTest();

        System.assertEquals(0, summary.batchCount);
        System.assertEquals(0, summary.totalRowsToday);
        System.assertEquals(0, summary.totalErrorsToday);
    }
}
