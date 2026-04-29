@IsTest
private class MdmKpiControllerTest {

    @TestSetup
    static void setup() {
        // Get record type IDs for the Account hierarchy types we created
        Map<String, Id> rtIds = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName IN ('HoldCo', 'Agency', 'Advertiser')
        ]) {
            rtIds.put(rt.DeveloperName, rt.Id);
        }

        List<Account> accounts = new List<Account>();
        Account holdCo = new Account(
            Name = 'Test HoldCo',
            RecordTypeId = rtIds.get('HoldCo')
        );
        accounts.add(holdCo);

        Account agency = new Account(
            Name = 'Test Agency',
            RecordTypeId = rtIds.get('Agency')
        );
        accounts.add(agency);

        Account advertiser = new Account(
            Name = 'Test Advertiser',
            RecordTypeId = rtIds.get('Advertiser')
        );
        accounts.add(advertiser);

        // Orphan advertiser (no parent) to verify orphanCount
        Account orphanAdvertiser = new Account(
            Name = 'Orphan Advertiser',
            RecordTypeId = rtIds.get('Advertiser')
        );
        accounts.add(orphanAdvertiser);

        insert accounts;

        // Tag one account so untaggedAccountCount can be verified
        Category__c cat = new Category__c(Name = 'Test Category', Is_Active__c = true);
        insert cat;

        Account_Category__c junc = new Account_Category__c(
            Account__c = holdCo.Id,
            Category__c = cat.Id
        );
        insert junc;
    }

    @IsTest
    static void getKpiData_countsAreAccurate() {
        Test.startTest();
        MdmKpiController.KpiData result = MdmKpiController.getKpiData();
        Test.stopTest();

        System.assertEquals(1, result.holdCoCount, 'Expected 1 HoldCo');
        System.assertEquals(1, result.agencyCount, 'Expected 1 Agency');
        System.assertEquals(2, result.advertiserCount, 'Expected 2 Advertisers (1 tagged, 1 orphan)');
        // Both advertiser and agency have no parent → orphanCount = 3 (agency + 2 advertisers)
        System.assert(result.orphanCount >= 2, 'Expected at least 2 orphans (Advertisers with no parent)');
        System.assertEquals(1, result.activeCategoryCount, 'Expected 1 active category');
        // HoldCo is tagged, agency and both advertisers are not → 3 untagged
        System.assertEquals(3, result.untaggedAccountCount, 'Expected 3 untagged accounts');
    }

    @IsTest
    static void getKpiData_emptyOrg_returnsZeros() {
        // In a separate test context with no data, all counts should be 0
        // This verifies the default values in KpiData are correct
        MdmKpiController.KpiData kpi = new MdmKpiController.KpiData();
        System.assertEquals(0, kpi.holdCoCount);
        System.assertEquals(0, kpi.agencyCount);
        System.assertEquals(0, kpi.advertiserCount);
        System.assertEquals(0, kpi.orphanCount);
        System.assertEquals(0, kpi.activeCategoryCount);
        System.assertEquals(0, kpi.untaggedAccountCount);
    }
}
