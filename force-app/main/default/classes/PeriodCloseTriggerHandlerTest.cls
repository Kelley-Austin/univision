@IsTest
private class PeriodCloseTriggerHandlerTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    static Period_Close__c makePc(Integer year, Integer month, String status) {
        return new Period_Close__c(
            Period_Year__c  = year,
            Period_Month__c = month,
            Close_Date__c   = Date.newInstance(year, month, 1).addDays(14),
            Status__c       = status,
            Composite_Key__c = year + '|' + String.valueOf(month).leftPad(2, '0')
        );
    }

    // ── isValidTransition unit tests ──────────────────────────────────────────

    @IsTest
    static void testValidTransitions() {
        System.assertEquals(true,  PeriodCloseTriggerHandler.isValidTransition('Open',     'Closed'),   'Open→Closed');
        System.assertEquals(true,  PeriodCloseTriggerHandler.isValidTransition('Closed',   'Reopened'), 'Closed→Reopened');
        System.assertEquals(true,  PeriodCloseTriggerHandler.isValidTransition('Reopened', 'Closed'),   'Reopened→Closed');
    }

    @IsTest
    static void testInvalidTransitions() {
        System.assertEquals(false, PeriodCloseTriggerHandler.isValidTransition('Open',     'Reopened'), 'Open→Reopened');
        System.assertEquals(false, PeriodCloseTriggerHandler.isValidTransition('Closed',   'Open'),     'Closed→Open');
        System.assertEquals(false, PeriodCloseTriggerHandler.isValidTransition('Reopened', 'Open'),     'Reopened→Open');
        System.assertEquals(false, PeriodCloseTriggerHandler.isValidTransition('Closed',   'Closed'),   'same-same');
    }

    // ── Integration via DML ───────────────────────────────────────────────────

    @IsTest
    static void testValidClose() {
        Period_Close__c pc = makePc(2026, 1, 'Open');
        insert pc;

        pc.Status__c = 'Closed';
        Test.startTest();
        update pc;
        Test.stopTest();

        System.assertEquals('Closed', [SELECT Status__c FROM Period_Close__c WHERE Id = :pc.Id].Status__c);
    }

    @IsTest
    static void testValidReopen() {
        Period_Close__c pc = makePc(2025, 12, 'Open');
        insert pc;
        pc.Status__c = 'Closed';
        update pc;

        pc.Status__c = 'Reopened';
        Test.startTest();
        update pc;
        Test.stopTest();

        System.assertEquals('Reopened', [SELECT Status__c FROM Period_Close__c WHERE Id = :pc.Id].Status__c);
    }

    @IsTest
    static void testBlockFutureReopen() {
        Date today = Date.today();
        Integer futureYear  = today.year() + 1;
        Integer futureMonth = today.month();

        Period_Close__c pc = makePc(futureYear, futureMonth, 'Open');
        insert pc;
        // Force it to Closed by bypassing trigger (set directly)
        // We can't normally close a future period via the service, but the trigger
        // only blocks re-open to future. Test the reopen block.
        pc.Status__c = 'Closed';
        update pc;

        pc.Status__c = 'Reopened';
        Test.startTest();
        Boolean threwError = false;
        try {
            update pc;
        } catch (DmlException e) {
            threwError = e.getMessage().contains('future period');
        }
        Test.stopTest();

        System.assert(threwError, 'Expected error when reopening future period');
    }

    @IsTest
    static void testInvalidTransitionViaUpdate() {
        Period_Close__c pc = makePc(2025, 11, 'Open');
        insert pc;

        pc.Status__c = 'Reopened'; // invalid: Open→Reopened
        Test.startTest();
        Boolean threwError = false;
        try {
            update pc;
        } catch (DmlException e) {
            threwError = e.getMessage().contains('Invalid status transition');
        }
        Test.stopTest();

        System.assert(threwError, 'Expected error for invalid transition');
    }

    @IsTest
    static void testNoStatusChange() {
        Period_Close__c pc = makePc(2026, 2, 'Open');
        insert pc;

        pc.Close_Date__c = Date.newInstance(2026, 2, 28); // change non-status field
        Test.startTest();
        update pc; // should succeed without error
        Test.stopTest();

        System.assertEquals('Open', [SELECT Status__c FROM Period_Close__c WHERE Id = :pc.Id].Status__c);
    }
}
