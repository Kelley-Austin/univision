@IsTest
private class PacingSnapshotBatchTest {

    @TestSetup
    static void makeData() {
        Account acct = new Account(Name = 'Test Advertiser');
        insert acct;

        Category__c cat = new Category__c(Name = 'Digital');
        insert cat;

        Integer yr = Date.today().year();
        Integer mo = Date.today().month();

        // Current-year projection (Won stage — should produce Booked)
        Projection__c won = new Projection__c(
            Account__c      = acct.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'National',
            Period_Year__c  = yr,
            Period_Month__c = mo,
            Amount__c       = 10000,
            Actual_Amount__c = 8000,
            Stage__c        = 'Won'
        );
        // Working-stage projection same period different revtype
        Projection__c working = new Projection__c(
            Account__c      = acct.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'Local',
            Period_Year__c  = yr,
            Period_Month__c = mo,
            Amount__c       = 5000,
            Actual_Amount__c = 0,
            Stage__c        = 'Working'
        );
        insert new List<Projection__c>{ won, working };

        // Budget record
        Budget__c bud = new Budget__c(
            Account__c      = acct.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'National',
            Period_Year__c  = yr
        );
        // Set the monthly field matching current month
        String mField = new String[]{ 'Jan','Feb','Mar','Apr','May','Jun',
                                      'Jul','Aug','Sep','Oct','Nov','Dec' }[mo - 1]
                      + '_Budget__c';
        bud.put(mField, 12000);
        insert bud;

        // Last-year actual (yr-1, same month)
        Actual_Revenue__c lyAct = new Actual_Revenue__c(
            Account__c      = acct.Id,
            Category__c     = cat.Id,
            Revenue_Type__c = 'National',
            Period_Year__c  = yr - 1,
            Period_Month__c = mo,
            Amount__c       = 9000,
            External_Key__c = acct.Id + '|Digital|National|' + (yr - 1) + '|' + mo
        );
        insert lyAct;
    }

    @IsTest
    static void testBatchCreatesSnapshots() {
        Test.startTest();
        Database.executeBatch(new PacingSnapshotBatch(), 200);
        Test.stopTest();

        List<Pacing_Snapshot__c> snaps = [
            SELECT Booked_Amount__c, Pending_Amount__c, Forecast_Amount__c,
                   Budget_Amount__c, Last_Year_Amount__c, Actual_Amount__c,
                   Snapshot_Date__c, Composite_Key__c
            FROM   Pacing_Snapshot__c
        ];
        Assert.isFalse(snaps.isEmpty(), 'Batch should create at least one snapshot');

        // Find the Won-stage snapshot
        Pacing_Snapshot__c wonSnap;
        for (Pacing_Snapshot__c s : snaps) {
            if (s.Booked_Amount__c != null && s.Booked_Amount__c > 0) { wonSnap = s; break; }
        }
        Assert.isNotNull(wonSnap, 'Should find a snapshot with booked amount');
        Assert.areEqual(10000, wonSnap.Booked_Amount__c, 'Won amount should be booked');
        Assert.areEqual(10000, wonSnap.Forecast_Amount__c, 'Forecast = Won * 1.0');
        Assert.areEqual(Date.today(), wonSnap.Snapshot_Date__c, 'Snapshot date = today');
        Assert.isTrue(String.isNotBlank(wonSnap.Composite_Key__c), 'Composite key must be populated');
    }

    @IsTest
    static void testBatchIdempotent() {
        // Run twice — second upsert should not create duplicates
        Test.startTest();
        Database.executeBatch(new PacingSnapshotBatch(), 200);
        Test.stopTest();

        Integer firstCount = [SELECT COUNT() FROM Pacing_Snapshot__c];

        Test.startTest();
        Database.executeBatch(new PacingSnapshotBatch(), 200);
        Test.stopTest();

        Integer secondCount = [SELECT COUNT() FROM Pacing_Snapshot__c];
        Assert.areEqual(firstCount, secondCount, 'Re-running batch should upsert, not duplicate');
    }

    @IsTest
    static void testWorkingStageWeighting() {
        Test.startTest();
        Database.executeBatch(new PacingSnapshotBatch(), 200);
        Test.stopTest();

        // Find the Working-stage snapshot (Local rev type)
        List<Pacing_Snapshot__c> snaps = [
            SELECT Revenue_Type__c, Booked_Amount__c, Pending_Amount__c, Forecast_Amount__c
            FROM   Pacing_Snapshot__c
            WHERE  Revenue_Type__c = 'Local'
        ];
        Assert.isFalse(snaps.isEmpty(), 'Should find Working-stage snapshot');
        Pacing_Snapshot__c ws = snaps[0];
        Assert.areEqual(0,   ws.Booked_Amount__c,   'Working should have 0 booked');
        Assert.areEqual(0,   ws.Pending_Amount__c,   'Working should have 0 pending');
        Assert.areEqual(500, ws.Forecast_Amount__c,  'Working forecast = 5000 * 0.1');
    }

    @IsTest
    static void testCustomDateConstructor() {
        Date testDate = Date.today().addDays(-1);
        Test.startTest();
        Database.executeBatch(new PacingSnapshotBatch(testDate), 200);
        Test.stopTest();

        List<Pacing_Snapshot__c> snaps = [
            SELECT Snapshot_Date__c FROM Pacing_Snapshot__c WHERE Snapshot_Date__c = :testDate
        ];
        Assert.isFalse(snaps.isEmpty(), 'Should create snapshots for custom date');
    }

    @IsTest
    static void testScheduler() {
        Test.startTest();
        System.schedule(
            'Test Pacing Scheduler',
            '0 0 2 * * ?',
            new PacingSnapshotScheduler()
        );
        Test.stopTest();
        // No assertion needed — just verifying no exception on schedule
    }
}
