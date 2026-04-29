@IsTest
private class PeriodCloseBatchTest {

    static Period_Close__c insertPc(Integer year, Integer month) {
        Period_Close__c pc = new Period_Close__c(
            Period_Year__c   = year,
            Period_Month__c  = month,
            Close_Date__c    = Date.newInstance(year, month, 14),
            Status__c        = 'Open',
            Composite_Key__c = year + '|' + String.valueOf(month).leftPad(2, '0')
        );
        insert pc;
        return pc;
    }

    @IsTest
    static void testBatchCreatesSnapshotsAndCloses() {
        Account a = new Account(Name = 'Batch Test Account');
        insert a;

        Period_Close__c pc = insertPc(2025, 2);

        List<Projection__c> projs = new List<Projection__c>();
        for (Integer i = 0; i < 5; i++) {
            projs.add(new Projection__c(
                Account__c      = a.Id,
                Period_Year__c  = 2025,
                Period_Month__c = 2,
                Amount__c       = 10000 * (i + 1),
                Actual_Amount__c = 9000 * (i + 1),
                Stage__c        = 'Working'
            ));
        }
        insert projs;

        Test.startTest();
        Database.executeBatch(new PeriodCloseBatch(pc.Id), 200);
        Test.stopTest();

        Period_Close__c updated = [SELECT Status__c, Closed_At__c FROM Period_Close__c WHERE Id = :pc.Id];
        System.assertEquals('Closed', updated.Status__c, 'Batch finish should set Closed');
        System.assertNotEquals(null, updated.Closed_At__c, 'Closed_At__c should be stamped');

        Integer snapCount = [SELECT COUNT() FROM Period_Snapshot__c WHERE Period_Close__c = :pc.Id];
        System.assertEquals(5, snapCount, 'Expected 5 snapshots');
    }

    @IsTest
    static void testBatchNoProjsStillCloses() {
        Period_Close__c pc = insertPc(2025, 1);

        Test.startTest();
        Database.executeBatch(new PeriodCloseBatch(pc.Id), 200);
        Test.stopTest();

        System.assertEquals('Closed', [SELECT Status__c FROM Period_Close__c WHERE Id = :pc.Id].Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Period_Snapshot__c WHERE Period_Close__c = :pc.Id]);
    }

    @IsTest
    static void testBatchUpsertIdempotent() {
        Account a = new Account(Name = 'Idempotent Test');
        insert a;

        Period_Close__c pc = insertPc(2025, 3);
        Projection__c proj = new Projection__c(
            Account__c = a.Id, Period_Year__c = 2025, Period_Month__c = 3,
            Amount__c = 50000, Actual_Amount__c = 45000, Stage__c = 'Working'
        );
        insert proj;

        // Run twice
        Test.startTest();
        Database.executeBatch(new PeriodCloseBatch(pc.Id), 200);
        // Re-open to allow second run
        pc.Status__c = 'Reopened';
        update pc;
        Database.executeBatch(new PeriodCloseBatch(pc.Id), 200);
        Test.stopTest();

        // Upsert by Snapshot_Composite_Key__c means still 1 snapshot
        System.assertEquals(1, [SELECT COUNT() FROM Period_Snapshot__c WHERE Period_Close__c = :pc.Id]);
    }

    @IsTest
    static void testSyncThresholdConstant() {
        System.assertEquals(200, PeriodCloseBatch.SYNC_THRESHOLD);
    }
}
