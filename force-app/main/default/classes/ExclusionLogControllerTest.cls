@IsTest
private class ExclusionLogControllerTest {

    @TestSetup
    static void makeData() {
        Integer yr = Date.today().year();
        List<Inbound_Staging__c> rows = new List<Inbound_Staging__c>();
        for (Integer i = 1; i <= 5; i++) {
            rows.add(new Inbound_Staging__c(
                Status__c              = 'Excluded',
                Raw_Advertiser_Name__c = 'Advertiser ' + i,
                Raw_Advertiser_Code__c = 'ADV-' + i,
                Revenue_Amount__c      = i * 1000,
                Revenue_Type__c        = 'National',
                Period_Year__c         = yr,
                Period_Month__c        = 3,
                Excluding_Rule__c      = 'NULL_GUID'
            ));
        }
        // One with a different rule
        rows.add(new Inbound_Staging__c(
            Status__c              = 'Excluded',
            Raw_Advertiser_Name__c = 'Bad Row',
            Revenue_Amount__c      = 500,
            Period_Year__c         = yr,
            Period_Month__c        = 3,
            Excluding_Rule__c      = 'MALFORMED_ROW'
        ));
        // Non-excluded row (should not appear)
        rows.add(new Inbound_Staging__c(
            Status__c              = 'Pending',
            Raw_Advertiser_Name__c = 'Active Row',
            Revenue_Amount__c      = 200,
            Period_Year__c         = yr,
            Period_Month__c        = 3
        ));
        insert rows;
    }

    @IsTest
    static void testGetExcludedRowsAll() {
        List<ExclusionLogController.ExclusionRow> rows =
            ExclusionLogController.getExcludedRows(50, 0, null, null);
        Assert.areEqual(6, rows.size(), 'Should return 6 excluded rows');
        for (ExclusionLogController.ExclusionRow r : rows) {
            Assert.isNotNull(r.stagingId,     'StagingId populated');
            Assert.isNotNull(r.excludingRule, 'Rule populated');
        }
    }

    @IsTest
    static void testGetExcludedRowsFilterByRule() {
        List<ExclusionLogController.ExclusionRow> rows =
            ExclusionLogController.getExcludedRows(50, 0, 'NULL_GUID', null);
        Assert.areEqual(5, rows.size(), 'Filter by NULL_GUID should return 5 rows');
    }

    @IsTest
    static void testGetExcludedRowsFilterByYear() {
        Integer yr = Date.today().year();
        List<ExclusionLogController.ExclusionRow> rows =
            ExclusionLogController.getExcludedRows(50, 0, null, yr);
        Assert.isFalse(rows.isEmpty(), 'Year filter should return rows for current year');
    }

    @IsTest
    static void testGetExcludedRowsPagination() {
        List<ExclusionLogController.ExclusionRow> page1 =
            ExclusionLogController.getExcludedRows(3, 0, null, null);
        List<ExclusionLogController.ExclusionRow> page2 =
            ExclusionLogController.getExcludedRows(3, 3, null, null);
        Assert.areEqual(3, page1.size(), 'Page 1 has 3 rows');
        Assert.areEqual(3, page2.size(), 'Page 2 has 3 rows');
        Assert.areNotEqual(page1[0].stagingId, page2[0].stagingId, 'Pages contain different rows');
    }

    @IsTest
    static void testRequeueRows() {
        List<Inbound_Staging__c> excluded = [
            SELECT Id FROM Inbound_Staging__c WHERE Status__c = 'Excluded' LIMIT 2
        ];
        List<Id> ids = new List<Id>{ excluded[0].Id, excluded[1].Id };

        ExclusionLogController.requeueRows(ids);

        List<Inbound_Staging__c> requeued = [
            SELECT Status__c, Excluding_Rule__c
            FROM   Inbound_Staging__c
            WHERE  Id IN :ids
        ];
        for (Inbound_Staging__c stg : requeued) {
            Assert.areEqual('Pending', stg.Status__c, 'Re-queued row should be Pending');
            Assert.isNull(stg.Excluding_Rule__c,      'Excluding rule cleared on re-queue');
        }
    }

    @IsTest
    static void testRequeueEmptyList() {
        // Should not throw
        ExclusionLogController.requeueRows(new List<Id>());
        ExclusionLogController.requeueRows(null);
    }

    @IsTest
    static void testGetExclusionRuleOptions() {
        List<String> options = ExclusionLogController.getExclusionRuleOptions();
        Assert.isFalse(options.isEmpty(), 'Should return at least one option');
        Assert.isTrue(options.contains('NULL_GUID'),    'NULL_GUID should be an option');
        Assert.isTrue(options.contains('MALFORMED_ROW'),'MALFORMED_ROW should be an option');
    }
}
