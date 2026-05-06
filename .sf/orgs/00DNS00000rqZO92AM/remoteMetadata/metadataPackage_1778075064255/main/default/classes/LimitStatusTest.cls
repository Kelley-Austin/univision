@IsTest
private class LimitStatusTest {
    @IsTest
    static void testLimitMethods() {
        // Test retrieval of limits map
        Map<String, System.OrgLimit> limits = LimitStatus.limitsMap;
        System.assertNotEquals(limits, null, 'limitsMap should not be null');
        System.assert(!limits.isEmpty(), 'limitsMap should not be empty');

        // Get a sample limit name
        String sampleLimit = limits.keySet().isEmpty() ? null : limits.keySet().iterator().next();
        System.assertNotEquals(sampleLimit, null, 'Sample limit name should not be null');

        // Test getLimitValue
        Integer limitValue = LimitStatus.getLimitValue(sampleLimit);
        System.assertNotEquals(limitValue, null, 'getLimitValue should return a non-null value');

        // Test getLimitTotal
        Integer limitTotal = LimitStatus.getLimitTotal(sampleLimit);
        System.assertNotEquals(limitTotal, null, 'getLimitTotal should return a non-null value');

        // Test getLimitAvail
        Integer limitAvailable = LimitStatus.getLimitAvail(sampleLimit);
        System.assertNotEquals(limitAvailable, null, 'getLimitAvail should return a non-null value');
        System.assertEquals(limitAvailable, limitTotal - limitValue, 'getLimitAvail should be total - used');

        // Test isLimitHit
        Boolean isHit = LimitStatus.isLimitHit(sampleLimit);
        System.assertEquals(isHit, limitAvailable <= 0, 'isLimitHit should return true if limit is reached');

        // Test stringVal
        String stringRepresentation = LimitStatus.stringVal;
        System.assertNotEquals(stringRepresentation, null, 'stringVal should return a non-null string');
        System.assert(stringRepresentation.contains(sampleLimit), 'stringVal should contain limit details');
    }
}