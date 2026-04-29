@IsTest
private class PitchProjectUnitCodeLinkerTest {

    // ── helpers ────────────────────────────────────────────────────────────

    private static Pitch_Project__c makeProject(String status) {
        Pitch_Project__c pp = new Pitch_Project__c(
            Project_Name__c = 'Test Project',
            Owner_Type__c   = 'Corporate',
            Goal__c         = 100000,
            Status__c       = status
        );
        insert pp;
        return pp;
    }

    private static void addOutlet(Id projectId, String unitCode) {
        insert new Pitch_Project_Outlet__c(
            Pitch_Project__c = projectId,
            Unit_Code__c     = unitCode
        );
    }

    // ── test 1: matching active project stamps the lookup ─────────────────

    @IsTest
    static void testMatchingCodeLinksActual() {
        Pitch_Project__c pp = makeProject('Active');
        addOutlet(pp.Id, 'UC-001');

        Actual_Revenue__c ar = new Actual_Revenue__c(
            Period_Year__c  = 2026,
            Period_Month__c = 4,
            Unit_Code__c    = 'UC-001'
        );

        Test.startTest();
        insert ar;
        Test.stopTest();

        ar = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :ar.Id];
        System.assertEquals(pp.Id, ar.Pitch_Project__c, 'Should link to matching Active project');
    }

    // ── test 2: no registered code — lookup stays null ────────────────────

    @IsTest
    static void testNoMatchLeavesNull() {
        makeProject('Active'); // project exists but no outlet for this code

        Actual_Revenue__c ar = new Actual_Revenue__c(
            Period_Year__c  = 2026,
            Period_Month__c = 4,
            Unit_Code__c    = 'UC-NO-MATCH'
        );
        insert ar;

        ar = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :ar.Id];
        System.assertNotEquals(null, ar, 'Record should exist');
        System.assertEquals(null, ar.Pitch_Project__c, 'Non-matching code should leave lookup null');
    }

    // ── test 3: inactive project (Draft) is not matched ───────────────────

    @IsTest
    static void testInactiveProjectSkipped() {
        Pitch_Project__c pp = makeProject('Draft');
        addOutlet(pp.Id, 'UC-DRAFT');

        Actual_Revenue__c ar = new Actual_Revenue__c(
            Period_Year__c  = 2026,
            Period_Month__c = 4,
            Unit_Code__c    = 'UC-DRAFT'
        );
        insert ar;

        ar = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :ar.Id];
        System.assertEquals(null, ar.Pitch_Project__c, 'Draft project should not attract unit-code links');
    }

    // ── test 4: existing link is never overwritten ────────────────────────

    @IsTest
    static void testExistingLinkNotOverwritten() {
        Pitch_Project__c pp1 = makeProject('Active');
        Pitch_Project__c pp2 = makeProject('Active');
        addOutlet(pp1.Id, 'UC-ORIG');
        addOutlet(pp2.Id, 'UC-ORIG');

        Actual_Revenue__c ar = new Actual_Revenue__c(
            Period_Year__c   = 2026,
            Period_Month__c  = 4,
            Unit_Code__c     = 'UC-ORIG',
            Pitch_Project__c = pp1.Id
        );
        insert ar;

        ar.Unit_Code__c = 'UC-ORIG'; // trigger update path
        update ar;

        ar = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :ar.Id];
        System.assertEquals(pp1.Id, ar.Pitch_Project__c, 'Existing link should never be overwritten');
    }

    // ── test 5: blank unit code is skipped ────────────────────────────────

    @IsTest
    static void testBlankUnitCodeSkipped() {
        Pitch_Project__c pp = makeProject('Active');
        addOutlet(pp.Id, '');

        Actual_Revenue__c ar = new Actual_Revenue__c(
            Period_Year__c  = 2026,
            Period_Month__c = 4
            // Unit_Code__c intentionally omitted
        );
        insert ar;

        ar = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :ar.Id];
        System.assertEquals(null, ar.Pitch_Project__c, 'Blank unit code should not trigger linking');
    }

    // ── test 6: update with unit code change links to correct project ─────

    @IsTest
    static void testUpdateOnCodeChangeLinks() {
        Pitch_Project__c pp = makeProject('Active');
        addOutlet(pp.Id, 'UC-UPDATE');

        Actual_Revenue__c ar = new Actual_Revenue__c(
            Period_Year__c  = 2026,
            Period_Month__c = 4,
            Unit_Code__c    = 'UC-NO-MATCH'
        );
        insert ar;

        ar = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :ar.Id];
        System.assertEquals(null, ar.Pitch_Project__c);

        ar.Unit_Code__c = 'UC-UPDATE';
        Test.startTest();
        update ar;
        Test.stopTest();

        ar = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :ar.Id];
        System.assertEquals(pp.Id, ar.Pitch_Project__c, 'Changing unit code should trigger re-link');
    }
}
