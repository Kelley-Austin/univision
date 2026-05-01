public class StrataTransformer implements SourceSystemTransformer {
    private static final Integer EXPECTED_COLS = 9;
    private static final String NULL_GUID = '00000000-0000-0000-0000-000000000000';

    public List<Inbound_Staging__c> transform(String fileContent, Id loadBatchId, Id sourceSystemId, String sourceSystemCode) {
        List<Inbound_Staging__c> results = new List<Inbound_Staging__c>();
        List<String> lines = fileContent.split('\n');
        Boolean firstLine = true;
        for (String line : lines) {
            line = line.replaceAll('\\s+$', '');
            if (firstLine) { firstLine = false; continue; }
            if (String.isBlank(line)) continue;
            List<String> cols = parseCsvLine(line);
            if (cols.size() < EXPECTED_COLS) {
                results.add(errorRow(loadBatchId, sourceSystemId, 'MALFORMED_ROW'));
                continue;
            }
            String advertiserId = cols[0].trim();
            String advertiser = cols[1].trim();
            String agency = cols[2].trim();
            String salesperson = cols[3].trim();
            Integer month = 0; Integer year = 0;
            try { month = Integer.valueOf(cols[4].trim()); } catch (Exception e) { month = 0; }
            try { year = Integer.valueOf(cols[5].trim()); } catch (Exception e) { year = 0; }
            Decimal amount = 0;
            try { amount = Decimal.valueOf(cols[6].trim().replace(',','')); } catch (Exception e) { amount = 0; }
            String revenueType = cols[7].trim();
            String outletCode = cols[8].trim();

            Inbound_Staging__c row = new Inbound_Staging__c(
                Source_System__c = sourceSystemId,
                Load_Batch__c = loadBatchId,
                Raw_Advertiser_Name__c = advertiser,
                Raw_Agency_Name__c = agency,
                Raw_Salesperson_Code__c = salesperson,
                Revenue_Amount__c = amount,
                Period_Month__c = month,
                Period_Year__c = year,
                Revenue_Type__c = revenueType,
                Outlet_Code__c = outletCode,
                Calendar_Type__c = 'Calendar',
                Status__c = advertiserId == NULL_GUID ? 'Excluded' : 'Pending',
                Excluding_Rule__c = advertiserId == NULL_GUID ? 'NULL_GUID_ADVERTISER' : null
            );
            results.add(row);
        }
        return results;
    }

    private List<String> parseCsvLine(String line) {
        List<String> fields = new List<String>();
        Boolean inQuotes = false;
        String current = '';
        for (Integer i = 0; i < line.length(); i++) {
            String c = line.substring(i, i+1);
            if (c == '"') {
                inQuotes = !inQuotes;
            } else if (c == ',' && !inQuotes) {
                fields.add(current);
                current = '';
            } else {
                current += c;
            }
        }
        fields.add(current);
        return fields;
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
