@IsTest
private class LateActualsControllerTest {

    // ── Test data helpers ─────────────────────────────────────────────────────

    static Actual_Revenue__c makeActual(Boolean isLate, String disposition) {
        Actual_Revenue__c a = new Actual_Revenue__c(
            Period_Year__c       = 2025,
            Period_Month__c      = 12,
            Revenue_Type__c      = 'TV',
            Revenue_Amount__c    = 10000,
            Is_Late__c           = isLate,
            Late_Disposition__c  = disposition
        );
        return a;
    }

    // ── getLateActuals ────────────────────────────────────────────────────────

    @IsTest
    static void testGetLateActualsReturnsOnlyPending() {
        List<Actual_Revenue__c> actuals = new List<Actual_Revenue__c>{
            makeActual(true,  null),      // pending (null)
            makeActual(true,  'Pending'), // pending (explicit)
            makeActual(true,  'Accepted'), // already accepted — excluded
            makeActual(false, null)        // not late — excluded
        };
        insert actuals;

        Test.startTest();
        LateActualsController.LateActualResult result =
            LateActualsController.getLateActuals(50, 0);
        Test.stopTest();

        System.assertEquals(2, result.totalCount, 'Expected 2 pending late actuals');
        System.assertEquals(2, result.rows.size());
        for (LateActualsController.LateActualRow row : result.rows) {
            System.assertEquals('Pending', row.disposition);
        }
    }

    @IsTest
    static void testGetLateActualsPagination() {
        List<Actual_Revenue__c> actuals = new List<Actual_Revenue__c>();
        for (Integer i = 0; i < 10; i++) {
            actuals.add(makeActual(true, null));
        }
        insert actuals;

        Test.startTest();
        LateActualsController.LateActualResult page1 = LateActualsController.getLateActuals(4, 0);
        LateActualsController.LateActualResult page2 = LateActualsController.getLateActuals(4, 4);
        Test.stopTest();

        System.assertEquals(10, page1.totalCount);
        System.assertEquals(4,  page1.rows.size());
        System.assertEquals(4,  page2.rows.size());
    }

    @IsTest
    static void testGetLateActualsEmpty() {
        Test.startTest();
        LateActualsController.LateActualResult result =
            LateActualsController.getLateActuals(50, 0);
        Test.stopTest();

        System.assertEquals(0, result.totalCount);
        System.assertEquals(0, result.rows.size());
    }

    // ── acceptLateActual ──────────────────────────────────────────────────────

    @IsTest
    static void testAcceptLateActual() {
        Actual_Revenue__c a = makeActual(true, null);
        insert a;

        Test.startTest();
        LateActualsController.acceptLateActual(a.Id);
        Test.stopTest();

        System.assertEquals('Accepted',
            [SELECT Late_Disposition__c FROM Actual_Revenue__c WHERE Id = :a.Id].Late_Disposition__c);
    }

    @IsTest
    static void testAcceptDoesNotAffectNonLateActuals() {
        Actual_Revenue__c notLate = makeActual(false, null);
        insert notLate;

        Test.startTest();
        LateActualsController.acceptLateActual(notLate.Id);
        Test.stopTest();

        // Is_Late__c = false — should be ignored by setDisposition WHERE clause
        System.assertEquals(null,
            [SELECT Late_Disposition__c FROM Actual_Revenue__c WHERE Id = :notLate.Id].Late_Disposition__c);
    }

    // ── rejectLateActual ──────────────────────────────────────────────────────

    @IsTest
    static void testRejectLateActual() {
        Actual_Revenue__c a = makeActual(true, 'Pending');
        insert a;

        Test.startTest();
        LateActualsController.rejectLateActual(a.Id);
        Test.stopTest();

        System.assertEquals('Rejected',
            [SELECT Late_Disposition__c FROM Actual_Revenue__c WHERE Id = :a.Id].Late_Disposition__c);
    }

    // ── bulkDispose ───────────────────────────────────────────────────────────

    @IsTest
    static void testBulkAccept() {
        List<Actual_Revenue__c> actuals = new List<Actual_Revenue__c>{
            makeActual(true, null), makeActual(true, null), makeActual(true, null)
        };
        insert actuals;
        List<Id> ids = new List<Id>{ actuals[0].Id, actuals[1].Id, actuals[2].Id };

        Test.startTest();
        LateActualsController.bulkDispose(ids, 'Accepted');
        Test.stopTest();

        for (Actual_Revenue__c a : [SELECT Late_Disposition__c FROM Actual_Revenue__c WHERE Id IN :ids]) {
            System.assertEquals('Accepted', a.Late_Disposition__c);
        }
    }

    @IsTest
    static void testBulkDisposeInvalidDisposition() {
        Actual_Revenue__c a = makeActual(true, null);
        insert a;

        Boolean threw = false;
        Test.startTest();
        try {
            LateActualsController.bulkDispose(new List<Id>{ a.Id }, 'Bogus');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected AuraHandledException for invalid disposition');
    }

    // ── setDisposition ────────────────────────────────────────────────────────

    @IsTest
    static void testSetDispositionBulk() {
        List<Actual_Revenue__c> actuals = new List<Actual_Revenue__c>{
            makeActual(true, null), makeActual(true, 'Pending')
        };
        insert actuals;

        Set<Id> ids = new Set<Id>{ actuals[0].Id, actuals[1].Id };

        Test.startTest();
        LateActualsController.setDisposition(ids, 'Rejected');
        Test.stopTest();

        for (Actual_Revenue__c a : [SELECT Late_Disposition__c FROM Actual_Revenue__c WHERE Id IN :ids]) {
            System.assertEquals('Rejected', a.Late_Disposition__c);
        }
    }

    @IsTest
    static void testGetLateActualsDefaultPageSize() {
        // No actuals inserted — should default cleanly without error
        Test.startTest();
        LateActualsController.LateActualResult result =
            LateActualsController.getLateActuals(null, null);
        Test.stopTest();

        System.assertEquals(0, result.totalCount);
    }
}
