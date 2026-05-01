@IsTest
private class PitchProjectControllerTest {

    // ── helpers ────────────────────────────────────────────────────────────

    private static Outlet__c makeOutlet(String name, Boolean active) {
        Outlet__c o = new Outlet__c(Name = name, Is_Active__c = active);
        insert o;
        return o;
    }

    private static Pitch_Project__c makeProject(Decimal goal, String status) {
        Pitch_Project__c pp = new Pitch_Project__c(
            Project_Name__c = 'Test Pitch',
            Owner_Type__c   = 'Corporate',
            Goal__c         = goal,
            Status__c       = status
        );
        insert pp;
        return pp;
    }

    private static Advertising_Opportunity__c makeOpp(Id pitchId) {
        Advertising_Opportunity__c opp = new Advertising_Opportunity__c(
            Pitch_Project__c = pitchId
        );
        insert opp;
        return opp;
    }

    private static Budget_Line__c makeLine(Id oppId, Decimal amount, String status) {
        Budget_Line__c bl = new Budget_Line__c(
            Advertising_Opportunity__c = oppId,
            Planned_Amount__c          = amount,
            Status__c                  = status,
            Month__c                   = 'April',
            Fiscal_Year__c             = 2026
        );
        insert bl;
        return bl;
    }

    // ── test 1: getActiveOutlets returns only active records ──────────────

    @IsTest
    static void testGetActiveOutletsReturnsActiveOnly() {
        makeOutlet('Active Outlet', true);
        makeOutlet('Inactive Outlet', false);

        Test.startTest();
        List<Outlet__c> results = PitchProjectController.getActiveOutlets();
        Test.stopTest();

        for (Outlet__c o : results) {
            System.assertEquals(true, o.Is_Active__c, 'Should only return active outlets');
        }
    }

    // ── test 2: saveProject creates project + junction records ────────────

    @IsTest
    static void testSaveProjectCreatesProjectAndJunctions() {
        Outlet__c outlet = makeOutlet('Test Outlet', true);

        Test.startTest();
        Id projId = PitchProjectController.saveProject(
            'My Pitch', 'Corporate', null, 'Q2 2026', 50000,
            Date.today(), Date.today().addDays(90), 'Description text',
            new List<Id>{ outlet.Id },
            new List<String>{ 'UC-TEST' }
        );
        Test.stopTest();

        System.assertNotEquals(null, projId, 'Should return new project Id');

        Pitch_Project__c proj = [SELECT Project_Name__c, Goal__c, Status__c FROM Pitch_Project__c WHERE Id = :projId];
        System.assertEquals('My Pitch', proj.Project_Name__c);
        System.assertEquals(50000, proj.Goal__c);
        System.assertEquals('Draft', proj.Status__c);

        List<Pitch_Project_Outlet__c> junctions = [
            SELECT Unit_Code__c, Outlet__c FROM Pitch_Project_Outlet__c WHERE Pitch_Project__c = :projId
        ];
        System.assertEquals(1, junctions.size(), 'Should create one junction record');
        System.assertEquals('UC-TEST', junctions[0].Unit_Code__c);
        System.assertEquals(outlet.Id, junctions[0].Outlet__c);
    }

    // ── test 3: saveProject with no outlets skips junction insert ─────────

    @IsTest
    static void testSaveProjectEmptyOutlets() {
        Test.startTest();
        Id projId = PitchProjectController.saveProject(
            'No Outlets', 'Corporate', null, null, 10000,
            null, null, null,
            new List<Id>(),
            new List<String>()
        );
        Test.stopTest();

        System.assertNotEquals(null, projId);
        Integer junctionCount = [SELECT COUNT() FROM Pitch_Project_Outlet__c WHERE Pitch_Project__c = :projId];
        System.assertEquals(0, junctionCount, 'No junctions should be created when no outlets provided');
    }

    // ── test 4: getPacingData aggregates booked/pending/forecast correctly ─

    @IsTest
    static void testGetPacingDataCorrectAggregates() {
        Pitch_Project__c pp = makeProject(100000, 'Active');
        Advertising_Opportunity__c opp = makeOpp(pp.Id);

        makeLine(opp.Id, 40000, 'Locked');   // booked
        makeLine(opp.Id, 20000, 'Approved'); // pending
        makeLine(opp.Id, 10000, 'Draft');    // pending
        makeLine(opp.Id, 5000,  'Cancelled'); // excluded

        Test.startTest();
        PitchProjectController.PacingData pd = PitchProjectController.getPacingData(pp.Id);
        Test.stopTest();

        System.assertEquals(100000, pd.goal,    'Goal should match project Goal__c');
        System.assertEquals(40000,  pd.booked,  'Booked = Locked lines only');
        System.assertEquals(30000,  pd.pending, 'Pending = Approved + Draft');
        // forecast = 40000*1.0 + 20000*0.6 + 10000*0.1 = 40000 + 12000 + 1000 = 53000
        System.assertEquals(53000,  pd.forecast, 'Forecast should be weighted sum');
    }

    // ── test 5: getPacingData throws on null projectId ─────────────────────

    @IsTest
    static void testGetPacingDataNullIdThrows() {
        Boolean threw = false;
        try {
            PitchProjectController.getPacingData(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should throw AuraHandledException for null projectId');
    }
}
