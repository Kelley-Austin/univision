@IsTest
private class LoadBatchDashboardControllerTest {

    @TestSetup
    static void setup() {
        Source_System__c ss = new Source_System__c(
            Name = 'WideOrbit TV',
            Code__c = 'WIDEORBIT_TV',
            Is_Active__c = true
        );
        insert ss;

        List<Load_Batch__c> batches = new List<Load_Batch__c>();
        for (Integer i = 0; i < 3; i++) {
            batches.add(new Load_Batch__c(
                Source_System__c = ss.Id,
                File_Name__c = 'test_' + i + '.tsv',
                Status__c = i == 0 ? 'Failed' : 'Complete',
                Row_Count__c = 100 + i * 10,
                Error_Count__c = i == 0 ? 5 : 0,
                Processed_At__c = Datetime.now().addMinutes(-i)
            ));
        }
        insert batches;
    }

    private static Source_System__c getSource() {
        return [SELECT Id FROM Source_System__c WHERE Code__c = 'WIDEORBIT_TV' LIMIT 1];
    }

    @IsTest
    static void getRecentBatches_returnsOrderedByDate() {
        Source_System__c ss = getSource();

        Test.startTest();
        List<Load_Batch__c> batches = LoadBatchDashboardController.getRecentBatches(ss.Id, 10);
        Test.stopTest();

        System.assertEquals(3, batches.size(), 'Should return all 3 batches');
        System.assertNotEquals(null, batches[0].File_Name__c);
        System.assertNotEquals(null, batches[0].Status__c);
    }

    @IsTest
    static void getRecentBatches_defaultLimit() {
        Source_System__c ss = getSource();

        Test.startTest();
        List<Load_Batch__c> batches = LoadBatchDashboardController.getRecentBatches(ss.Id, null);
        Test.stopTest();

        System.assertEquals(3, batches.size(), 'Null limit should default to 20');
    }

    @IsTest
    static void getRecentBatches_zeroLimit_defaultsTo20() {
        Source_System__c ss = getSource();

        Test.startTest();
        List<Load_Batch__c> batches = LoadBatchDashboardController.getRecentBatches(ss.Id, 0);
        Test.stopTest();

        System.assertEquals(3, batches.size());
    }

    @IsTest
    static void getSummary_aggregatesRowsAndErrors() {
        Source_System__c ss = getSource();

        Test.startTest();
        LoadBatchDashboardController.BatchSummary summary = LoadBatchDashboardController.getSummary(ss.Id);
        Test.stopTest();

        System.assertEquals(3, summary.batchCount, 'Should count 3 batches');
        System.assert(summary.totalRowsToday >= 0, 'totalRowsToday should not be negative');
        System.assert(summary.totalErrorsToday >= 0, 'totalErrorsToday should not be negative');
    }

    @IsTest
    static void getSummary_noMatchingSource_returnsZeroes() {
        Source_System__c otherSs = new Source_System__c(
            Name = 'Strata', Code__c = 'STRATA', Is_Active__c = true
        );
        insert otherSs;

        Test.startTest();
        LoadBatchDashboardController.BatchSummary summary = LoadBatchDashboardController.getSummary(otherSs.Id);
        Test.stopTest();

        System.assertEquals(0, summary.batchCount);
        System.assertEquals(0, summary.totalRowsToday);
        System.assertEquals(0, summary.totalErrorsToday);
    }
}
