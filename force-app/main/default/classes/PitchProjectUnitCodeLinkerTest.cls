@IsTest
private class PitchProjectUnitCodeLinkerTest {

    // ── Test data helpers ─────────────────────────────────────────────────────

    private static Pitch_Project__c makeProject(String status) {
        Pitch_Project__c p = new Pitch_Project__c(
            Project_Name__c = 'Test Pitch',
            Owner_Type__c   = 'Corporate',
            Goal__c         = 100000,
            Status__c       = status
        );
        insert p;
        return p;
    }

    private static Outlet__c makeOutlet(String name) {
        Outlet__c o = new Outlet__c(Name = name, Is_Active__c = true);
        insert o;
        return o;
    }

    private static Pitch_Project_Outlet__c makeJunction(Id projectId, Id outletId, String code) {
        Pitch_Project_Outlet__c j = new Pitch_Project_Outlet__c(
            Pitch_Project__c = projectId,
            Outlet__c        = outletId,
            Unit_Code__c     = code
        );
        insert j;
        return j;
    }

    private static Account makeAccount() {
        Id rtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Advertiser').getRecordTypeId();
        Account a = new Account(Name = 'Linker Test Adv', RecordTypeId = rtId);
        insert a;
        return a;
    }

    private static Actual_Revenue__c makeActual(Id accountId, String unitCode, Id projectId) {
        return new Actual_Revenue__c(
            Account__c        = accountId,
            Revenue_Type__c   = 'National TV',
            Period_Month__c   = 4,
            Period_Year__c    = 2026,
            Revenue_Amount__c = 5000,
            External_Key__c   = 'EXT-LNK-' + unitCode,
            Unit_Code__c      = unitCode,
            Pitch_Project__c  = projectId
        );
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    @IsTest
    static void testLink_matchingActiveProject() {
        Pitch_Project__c proj = makeProject('Active');
        Outlet__c outlet      = makeOutlet('KMEX');
        makeJunction(proj.Id, outlet.Id, 'KMEX-30');
        Account adv           = makeAccount();

        Actual_Revenue__c a = makeActual(adv.Id, 'KMEX-30', null);

        Test.startTest();
        insert a;
        Test.stopTest();

        a = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.areEqual(proj.Id, a.Pitch_Project__c, 'Actual should be linked to matching Active project');
    }

    @IsTest
    static void testLink_noMatchNoChange() {
        makeProject('Active');
        Account adv = makeAccount();

        Actual_Revenue__c a = makeActual(adv.Id, 'NO-MATCH-CODE', null);
        Test.startTest();
        insert a;
        Test.stopTest();

        a = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.isNull(a.Pitch_Project__c, 'Unmatched unit code should leave Pitch_Project__c null');
    }

    @IsTest
    static void testLink_inactiveProjectSkipped() {
        Pitch_Project__c proj = makeProject('Draft');
        Outlet__c outlet      = makeOutlet('UNIMAS');
        makeJunction(proj.Id, outlet.Id, 'UNIMAS-60');
        Account adv           = makeAccount();

        Actual_Revenue__c a = makeActual(adv.Id, 'UNIMAS-60', null);
        Test.startTest();
        insert a;
        Test.stopTest();

        a = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.isNull(a.Pitch_Project__c, 'Draft project should not trigger auto-link');
    }

    @IsTest
    static void testLink_alreadyLinkedNotOverwritten() {
        Pitch_Project__c proj1 = makeProject('Active');
        Pitch_Project__c proj2 = makeProject('Active');
        Outlet__c outlet       = makeOutlet('GALAVISION');
        makeJunction(proj1.Id, outlet.Id, 'GAL-15');
        makeJunction(proj2.Id, outlet.Id, 'GAL-15');
        Account adv            = makeAccount();

        // Insert pre-linked to proj2
        Actual_Revenue__c a = makeActual(adv.Id, 'GAL-15', proj2.Id);
        Test.startTest();
        insert a;
        Test.stopTest();

        a = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.areEqual(proj2.Id, a.Pitch_Project__c, 'Pre-linked record should not be overwritten');
    }

    @IsTest
    static void testLink_blankUnitCodeSkipped() {
        makeProject('Active');
        Account adv = makeAccount();

        Actual_Revenue__c a = makeActual(adv.Id, null, null);
        a.External_Key__c   = 'EXT-LNK-BLANK';
        Test.startTest();
        insert a;
        Test.stopTest();

        a = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.isNull(a.Pitch_Project__c, 'Blank unit code should never trigger linking');
    }

    @IsTest
    static void testLink_updateTriggersRelinkOnCodeChange() {
        Pitch_Project__c proj = makeProject('Active');
        Outlet__c outlet      = makeOutlet('TDN');
        makeJunction(proj.Id, outlet.Id, 'TDN-30');
        Account adv           = makeAccount();

        Actual_Revenue__c a = makeActual(adv.Id, 'OTHER-CODE', null);
        insert a;

        a = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.isNull(a.Pitch_Project__c);

        a.Unit_Code__c = 'TDN-30';
        Test.startTest();
        update a;
        Test.stopTest();

        a = [SELECT Pitch_Project__c FROM Actual_Revenue__c WHERE Id = :a.Id];
        Assert.areEqual(proj.Id, a.Pitch_Project__c, 'Updating unit code to matching value should trigger link');
    }
}
