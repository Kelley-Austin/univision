public class WideOrbitTransformer implements SourceSystemTransformer {
    private static final Integer EXPECTED_COLS = 7;

    public List<Inbound_Staging__c> transform(String fileContent, Id loadBatchId, Id sourceSystemId, String sourceSystemCode) {
        Map<String, String> revenueCodeMap = loadRevenueCodeMap(sourceSystemCode);
        List<Inbound_Staging__c> results = new List<Inbound_Staging__c>();
        List<String> lines = fileContent.split('\n');
        Boolean firstLine = true;
        for (String line : lines) {
            line = line.stripTrailing();
            if (firstLine) { firstLine = false; continue; }
            if (String.isBlank(line)) continue;
            List<String> cols = line.split('\t');
            if (cols.size() < EXPECTED_COLS) {
                results.add(errorRow(loadBatchId, sourceSystemId, 'MALFORMED_ROW'));
                continue;
            }
            String advertiser = cols[0].trim();
            String agency = cols[1].trim();
            String ae = cols[2].trim();
            String airDate = cols[3].trim();
            String amountStr = cols[4].trim().replace(',', '');
            String spotTypeCode = cols[5].trim();
            String station = cols[6].trim();

            Integer month = 0; Integer year = 0;
            try {
                List<String> dateParts = airDate.split('/');
                month = Integer.valueOf(dateParts[0]);
                year = Integer.valueOf(dateParts[2]);
            } catch (Exception e) {
                results.add(errorRow(loadBatchId, sourceSystemId, 'INVALID_DATE'));
                continue;
            }

            Decimal amount = 0;
            try { amount = Decimal.valueOf(amountStr); } catch (Exception e) { amount = 0; }

            String revenueType = revenueCodeMap.containsKey(spotTypeCode) ? revenueCodeMap.get(spotTypeCode) : spotTypeCode;

            Inbound_Staging__c row = new Inbound_Staging__c(
                Source_System__c = sourceSystemId,
                Load_Batch__c = loadBatchId,
                Raw_Advertiser_Name__c = advertiser,
                Raw_Agency_Name__c = agency,
                Raw_Salesperson_Code__c = ae,
                Revenue_Amount__c = amount,
                Period_Month__c = month,
                Period_Year__c = year,
                Revenue_Type__c = revenueType,
                Outlet_Code__c = station,
                Calendar_Type__c = 'Calendar',
                Status__c = 'Pending'
            );
            results.add(row);
        }
        return results;
    }

    private Map<String, String> loadRevenueCodeMap(String sourceSystemCode) {
        Map<String, String> m = new Map<String, String>();
        for (Revenue_Code_Mapping__mdt rec : [
            SELECT Source_Code__c, Revenue_Type__c
            FROM Revenue_Code_Mapping__mdt
            WHERE Source_System_Code__c = :sourceSystemCode
        ]) {
            m.put(rec.Source_Code__c, rec.Revenue_Type__c);
        }
        return m;
    }

    private Inbound_Staging__c errorRow(Id loadBatchId, Id sourceSystemId, String rule) {
        return new Inbound_Staging__c(
            Source_System__c = sourceSystemId,
            Load_Batch__c = loadBatchId,
            Status__c = 'Error',
            Excluding_Rule__c = rule
        );
    }
}
