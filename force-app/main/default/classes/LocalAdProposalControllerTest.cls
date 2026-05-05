@IsTest
private class LocalAdProposalControllerTest {

    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Test Advertiser');
        insert acct;

        Channel__c ch = new Channel__c(
            Name = 'KUVN',
            Status__c = 'Active',
            Channel_Type__c = 'TV'
        );
        insert ch;

        Vehicle__c v = new Vehicle__c(
            Name = 'Gold Network',
            Status__c = 'Active',
            Day_Part__c = 'Prime',
            Rate_Card__c = 5000
        );
        insert v;

        Id rtId = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('Local_Ad_Sales')
            .getRecordTypeId();

        Opportunity opp = new Opportunity(
            Name              = 'Local Ad Test Opp',
            RecordTypeId      = rtId,
            AccountId         = acct.Id,
            CloseDate         = Date.today().addMonths(3),
            Market__c         = 'Los Angeles',
            Start_Date__c     = Date.today(),
            End_Date__c       = Date.today().addMonths(3),
            Primary_Demo__c   = 'A18-49',
            Secondary_Demo__c = 'W25-54',
            Proposal_Notes__c = 'Test proposal notes',
            Total_Budget__c   = 50000,
            StageName         = 'Draft'
        );
        insert opp;

        Budget_Line__c bl = new Budget_Line__c(
            Opportunity__c = opp.Id,
            Account__c   = acct.Id,
            Vehicle__c   = v.Id,
            Channel__c   = ch.Id,
            Month__c     = 'January',
            Fiscal_Year__c = '2026',
            Planned_Amount__c = 10000,
            Status__c    = 'Draft'
        );
        insert bl;
    }

    @IsTest
    static void testControllerHappyPath() {
        Opportunity opp =
            [SELECT Id FROM Opportunity LIMIT 1];

        Test.setCurrentPageReference(new PageReference('/apex/LocalAdProposal'));
        ApexPages.currentPage().getParameters().put('id', opp.Id);

        Test.startTest();
        LocalAdProposalController ctrl = new LocalAdProposalController();
        Test.stopTest();

        System.assertEquals(false, ctrl.hasError, ctrl.errorMessage);
        System.assertNotEquals(null, ctrl.opp);
        System.assertNotEquals(null, ctrl.advertiser);
        System.assertEquals(1, ctrl.budgetLines.size());
        System.assertEquals(10000, ctrl.totalPlanned);
        System.assertEquals('Los Angeles', ctrl.opp.Market__c);
    }

    @IsTest
    static void testControllerNoId() {
        Test.setCurrentPageReference(new PageReference('/apex/LocalAdProposal'));

        Test.startTest();
        LocalAdProposalController ctrl = new LocalAdProposalController();
        Test.stopTest();

        System.assertEquals(true, ctrl.hasError);
        System.assertNotEquals(null, ctrl.errorMessage);
        System.assertEquals(null, ctrl.opp);
    }

    @IsTest
    static void testControllerInvalidId() {
        Test.setCurrentPageReference(new PageReference('/apex/LocalAdProposal'));
        ApexPages.currentPage().getParameters().put('id', 'not_a_real_id_xyz');

        Test.startTest();
        LocalAdProposalController ctrl = new LocalAdProposalController();
        Test.stopTest();

        System.assertEquals(true, ctrl.hasError);
        System.assertNotEquals(null, ctrl.errorMessage);
    }

    @IsTest
    static void testTotalPlannedSumsAllLines() {
        Opportunity opp =
            [SELECT Id FROM Opportunity LIMIT 1];
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Channel__c ch = [SELECT Id FROM Channel__c LIMIT 1];
        Vehicle__c v  = [SELECT Id FROM Vehicle__c LIMIT 1];

        Budget_Line__c bl2 = new Budget_Line__c(
            Opportunity__c = opp.Id,
            Account__c   = acct.Id,
            Vehicle__c   = v.Id,
            Channel__c   = ch.Id,
            Month__c     = 'February',
            Fiscal_Year__c = '2026',
            Planned_Amount__c = 5000,
            Status__c    = 'Draft'
        );
        insert bl2;

        Test.setCurrentPageReference(new PageReference('/apex/LocalAdProposal'));
        ApexPages.currentPage().getParameters().put('id', opp.Id);

        Test.startTest();
        LocalAdProposalController ctrl = new LocalAdProposalController();
        Test.stopTest();

        System.assertEquals(false, ctrl.hasError);
        System.assertEquals(2, ctrl.budgetLines.size());
        System.assertEquals(15000, ctrl.totalPlanned, 'Should sum both budget lines');
    }
}
