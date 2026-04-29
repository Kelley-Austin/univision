/**
 * Transformer for Counterpoint export files.
 *
 * File characteristics:
 *   - Encoding: CP1252 (Windows-1252) — extended Latin characters common in
 *     broadcast-station names and advertiser names.
 *   - Delimiter: comma (CSV)
 *
 * Exclusion rules:
 *   - MALFORMED_ROW: column count does not match header
 *   - BLANK_ADVERTISER: advertiser column is empty
 */
public class CounterpointTransformer extends TransformerBase implements ITransformer {

    private static final String DELIMITER = ',';

    public List<Inbound_Staging__c> transform(Blob fileContent, Id sourceSystemId, Boolean dryRun) {
        String content = decodeCp1252(fileContent);
        List<Inbound_Staging__c> results = new List<Inbound_Staging__c>();

        if (String.isBlank(content)) return results;

        List<String> lines = content.split('\n');
        if (lines.isEmpty()) return results;

        Integer headerIdx = 0;
        while (headerIdx < lines.size() && String.isBlank(lines[headerIdx])) headerIdx++;
        if (headerIdx >= lines.size()) return results;

        List<String> headerCols = parseLine(lines[headerIdx].removeEnd('\r'), DELIMITER);
        Map<String, Integer> hdr = buildHeaderMap(headerCols);
        Integer expectedCols = headerCols.size();

        Integer colAdvertiser = hdr.get('advertiser');
        Integer colAgency     = hdr.get('agency');
        Integer colStation    = hdr.get('station');
        Integer colRevType    = hdr.get('type');
        Integer colAmount     = hdr.get('amount');
        Integer colAeCode     = hdr.get('ae');
        Integer colPeriod     = hdr.get('period');

        for (Integer i = headerIdx + 1; i < lines.size(); i++) {
            String line = lines[i].removeEnd('\r');
            if (String.isBlank(line)) continue;

            List<String> cols = parseLine(line, DELIMITER);
            Inbound_Staging__c row = new Inbound_Staging__c(
                Source_System__c = sourceSystemId,
                Raw_Record__c    = line.abbreviate(32768)
            );

            if (cols.size() < expectedCols) {
                row.Status__c         = 'Excluded';
                row.Excluding_Rule__c = 'MALFORMED_ROW';
                row.External_Key__c   = buildExternalKey('COUNTERPOINT', line);
                results.add(row);
                continue;
            }

            String advertiserName = safeGet(cols, colAdvertiser);
            if (String.isBlank(advertiserName)) {
                row.Status__c         = 'Excluded';
                row.Excluding_Rule__c = 'BLANK_ADVERTISER';
                row.External_Key__c   = buildExternalKey('COUNTERPOINT', line);
                results.add(row);
                continue;
            }

            row.Advertiser_Name__c  = advertiserName;
            row.Agency_Name__c      = safeGet(cols, colAgency);
            row.Station_Code__c     = safeGet(cols, colStation);
            row.Revenue_Type__c     = safeGet(cols, colRevType);
            row.Revenue_Amount__c   = parseCurrency(safeGet(cols, colAmount));
            row.AE_Code__c          = safeGet(cols, colAeCode);
            row.Broadcast_Period__c = safeGet(cols, colPeriod);
            row.Status__c           = 'Pending';
            row.External_Key__c     = buildExternalKey('COUNTERPOINT', line);
            results.add(row);
        }

        return results;
    }
}
