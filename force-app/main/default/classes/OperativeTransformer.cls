public class OperativeTransformer implements SourceSystemTransformer {
    private static final Integer EXPECTED_COLS = 11;

    public List<Inbound_Staging__c> transform(String fileContent, Id loadBatchId, Id sourceSystemId, String sourceSystemCode) {
        List<Inbound_Staging__c> results = new List<Inbound_Staging__c>();
        List<String> lines = fileContent.split('\n');
        Boolean firstLine = true;
        for (String line : lines) {
            line = line.stripTrailing();
            if (firstLine) { firstLine = false; continue; }
            if (String.isBlank(line)) continue;
            List<String> cols = parseCsvLine(line);
            if (cols.size() < EXPECTED_COLS) {
                results.add(errorRow(loadBatchId, sourceSystemId, 'MALFORMED_ROW'));
                continue;
            }
            String advertiser = cols[0].trim();
            String agency = cols[1].trim();
            String rep = cols[2].trim();
            Integer calMonth = 0; Integer calYear = 0;
            try { calMonth = Integer.valueOf(cols[3].trim()); } catch (Exception e) {}
            try { calYear = Integer.valueOf(cols[4].trim()); } catch (Exception e) {}
            Decimal calAmount = 0;
            try { calAmount = Decimal.valueOf(cols[5].trim().replace(',','')); } catch (Exception e) {}
            Integer bcMonth = 0; Integer bcYear = 0;
            try { bcMonth = Integer.valueOf(cols[6].trim()); } catch (Exception e) {}
            try { bcYear = Integer.valueOf(cols[7].trim()); } catch (Exception e) {}
            Decimal bcAmount = 0;
            try { bcAmount = Decimal.valueOf(cols[8].trim().replace(',','')); } catch (Exception e) {}
            String revenueType = cols[9].trim();
            String outletCode = cols[10].trim();

            // Calendar row
            results.add(new Inbound_Staging__c(
                Source_System__c = sourceSystemId,
                Load_Batch__c = loadBatchId,
                Raw_Advertiser_Name__c = advertiser,
                Raw_Agency_Name__c = agency,
                Raw_Salesperson_Code__c = rep,
                Revenue_Amount__c = calAmount,
                Period_Month__c = calMonth,
                Period_Year__c = calYear,
                Revenue_Type__c = revenueType,
                Outlet_Code__c = outletCode,
                Calendar_Type__c = 'Calendar',
                Status__c = 'Pending'
            ));

            // Broadcast row
            results.add(new Inbound_Staging__c(
                Source_System__c = sourceSystemId,
                Load_Batch__c = loadBatchId,
                Raw_Advertiser_Name__c = advertiser,
                Raw_Agency_Name__c = agency,
                Raw_Salesperson_Code__c = rep,
                Revenue_Amount__c = bcAmount,
                Period_Month__c = bcMonth,
                Period_Year__c = bcYear,
                Revenue_Type__c = revenueType,
                Outlet_Code__c = outletCode,
                Calendar_Type__c = 'Broadcast',
                Status__c = 'Pending'
            ));
        }
        return results;
    }

    private List<String> parseCsvLine(String line) {
        List<String> fields = new List<String>();
        Boolean inQuotes = false; String current = '';
        for (Integer i = 0; i < line.length(); i++) {
            String c = line.substring(i, i+1);
            if (c == '"') { inQuotes = !inQuotes; }
            else if (c == ',' && !inQuotes) { fields.add(current); current = ''; }
            else { current += c; }
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
