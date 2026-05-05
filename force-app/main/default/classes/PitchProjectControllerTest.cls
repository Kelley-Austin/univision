@IsTest
private class PitchProjectControllerTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Account makeAccount() {
        Id rtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();
        Account a = new Account(Name = 'Pacing Test Adv', RecordTypeId = rtId);
        insert a;
        return a;
    }

    private static Opportunity makeOpp(Id accountId, Id projectId,
                                       String status, Decimal amount) {
        // Standard Opportunity FiscalYear is read-only and derived from CloseDate.
        Opportunity opp = new Opportunity(
            Name                     = 'Pitch Test Opp',
            AccountId                = accountId,
            StageName                = status,
            CloseDate                = Date.newInstance(2026, 6, 30),
            Total_Planned_Amount__c  = amount,
            Pitch_Project__c         = projectId
        );
        insert opp;
        return opp;
    }

    // ── getActiveOutlets ──────────────────────────────────────────────────────

    @IsTest
    static void testGetActiveOutlets_returnsActiveOnly() {
        Outlet__c active   = new Outlet__c(Name = 'Active Outlet',   Is_Active__c = true);
        Outlet__c inactive = new Outlet__c(Name = 'Inactive Outlet', Is_Active__c = false);
        insert new List<Outlet__c>{ active, inactive };

        Test.startTest();
        List<Outlet__c> results = PitchProjectController.getActiveOutlets();
        Test.stopTest();

        Boolean foundInactive = false;
        for (Outlet__c o : results) {
            if (o.Id == inactive.Id) foundInactive = true;
        }
        Assert.isFalse(foundInactive, 'Inactive outlet should not be returned');
    }

    // ── saveProject ───────────────────────────────────────────────────────────

    @IsTest
    static void testSaveProject_createsProjectAndJunctions() {
        Outlet__c o1 = new Outlet__c(Name = 'Outlet A', Is_Active__c = true);
        Outlet__c o2 = new Outlet__c(Name = 'Outlet B', Is_Active__c = true);
        insert new List<Outlet__c>{ o1, o2 };

        List<Map<String, String>> outlets = new List<Map<String, String>>{
            new Map<String, String>{ 'outletId' => o1.Id, 'unitCode' => 'CODE-A' },
            new Map<String, String>{ 'outletId' => o2.Id, 'unitCode' => 'CODE-B' }
        };

        Test.startTest();
        Id projId = PitchProjectController.saveProject(
            'Q3 BMW Pitch', 'Corporate', null, 'Q3 2026',
            250000, 'Test description', '2026-07-01', '2026-09-30', outlets
        );
        Test.stopTest();

        Assert.isNotNull(projId, 'saveProject should return a non-null Id');

        Pitch_Project__c proj = [
            SELECT Project_Name__c, Owner_Type__c, Goal__c, Status__c
            FROM   Pitch_Project__c WHERE Id = :projId
        ];
        Assert.areEqual('Q3 BMW Pitch', proj.Project_Name__c);
        Assert.areEqual('Corporate',    proj.Owner_Type__c);
        Assert.areEqual(250000,         proj.Goal__c);
        Assert.areEqual('Active',       proj.Status__c);

        List<Pitch_Project_Outlet__c> junctions = [
            SELECT Unit_Code__c FROM Pitch_Project_Outlet__c WHERE Pitch_Project__c = :projId
        ];
        Assert.areEqual(2, junctions.size(), 'Two junction records should be created');
    }

    @IsTest
    static void testSaveProject_emptyOutletsStillCreatesProject() {
        Test.startTest();
        Id projId = PitchProjectController.saveProject(
            'Solo Pitch', 'Market', null, 'H1 2026',
            50000, null, null, null, new List<Map<String, String>>()
        );
        Test.stopTest();

        Assert.isNotNull(projId);
        Integer junctionCount = [
            SELECT COUNT() FROM Pitch_Project_Outlet__c WHERE Pitch_Project__c = :projId
        ];
        Assert.areEqual(0, junctionCount);
    }

    // ── getPacingData ─────────────────────────────────────────────────────────

    @IsTest
    static void testGetPacingData_correctAggregates() {
        Account adv = makeAccount();
        Pitch_Project__c proj = new Pitch_Project__c(
            Project_Name__c = 'Pacing Test', Owner_Type__c = 'Corporate',
            Goal__c = 1000000, Status__c = 'Active'
        );
        insert proj;

        // Booked: Active + Closed → 300k + 200k = 500k
        makeOpp(adv.Id, proj.Id, 'Active', 300000);
        makeOpp(adv.Id, proj.Id, 'Closed', 200000);
        // Pending: Submitted + Approved → 100k + 150k = 250k
        makeOpp(adv.Id, proj.Id, 'Submitted', 100000);
        makeOpp(adv.Id, proj.Id, 'Approved',  150000);
        // Cancelled: should be excluded from forecast
        makeOpp(adv.Id, proj.Id, 'Cancelled', 999999);

        Test.startTest();
        PitchProjectController.PacingData pd = PitchProjectController.getPacingData(proj.Id);
        Test.stopTest();

        Assert.areEqual(1000000, pd.goal);
        Assert.areEqual(500000,  pd.booked,  'Booked = Active + Closed opps');
        Assert.areEqual(250000,  pd.pending, 'Pending = Submitted + Approved opps');

        // Forecast (weighted): 300k*1.0 + 200k*1.0 + 100k*0.30 + 150k*0.60 = 500k + 30k + 90k = 620k
        Assert.areEqual(620000, pd.forecast.setScale(0), 'Weighted forecast mismatch');
    }

    @IsTest
    static void testGetPacingData_nullProjectIdThrows() {
        Boolean threw = false;
        try {
            PitchProjectController.getPacingData(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Null projectId should throw AuraHandledException');
    }

    @IsTest
    static void testGetPacingData_noOppsReturnsZeros() {
        Pitch_Project__c proj = new Pitch_Project__c(
            Project_Name__c = 'Empty Project', Owner_Type__c = 'Market',
            Goal__c = 500000, Status__c = 'Active'
        );
        insert proj;

        Test.startTest();
        PitchProjectController.PacingData pd = PitchProjectController.getPacingData(proj.Id);
        Test.stopTest();

        Assert.areEqual(0, pd.booked);
        Assert.areEqual(0, pd.pending);
        Assert.areEqual(0, pd.forecast);
    }
}
