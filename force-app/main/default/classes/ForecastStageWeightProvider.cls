/**
 * Reads Forecast_Stage_Weight__mdt and exposes a stage-name → weight-percent map.
 * Cached for the transaction. Tests can override via setMockWeights.
 */
public with sharing class ForecastStageWeightProvider {

    @TestVisible
    private static Map<String, Decimal> mockWeights;

    private static Map<String, Decimal> cache;

    public static Map<String, Decimal> getWeights() {
        if (mockWeights != null) return mockWeights;
        if (cache != null) return cache;
        cache = new Map<String, Decimal>();
        for (Forecast_Stage_Weight__mdt w : [
            SELECT Stage_Name__c, Weight_Pct__c FROM Forecast_Stage_Weight__mdt
        ]) {
            cache.put(w.Stage_Name__c, w.Weight_Pct__c);
        }
        return cache;
    }

    public static Decimal getWeight(String stage) {
        if (stage == null) return 0;
        Decimal w = getWeights().get(stage);
        return w == null ? 0 : w;
    }

    @TestVisible
    private static void setMockWeights(Map<String, Decimal> mock) {
        mockWeights = mock;
        cache = null;
    }
}
