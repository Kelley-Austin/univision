/**
 * Batch Apex that processes a Counterpoint CSV file (uploaded as a Salesforce File)
 * and upserts Actuals_Record__c records keyed on Counterpoint_Order_ID__c.
 *
 * Usage:
 *   Database.executeBatch(new CounterpointIngestionBatch(contentVersionId, fileName), 200);
 *
 * The batch reads the file once in start(), detects the date variant from the header,
 * then processes data rows in chunks of up to 200 per execute() call.
 * Three SOQL queries per execute() chunk resolve Channel__c, Vehicle__c, and Account lookups
 * in bulk to stay well within governor limits.
 */
public class CounterpointIngestionBatch implements Database.Batchable<String>, Database.Stateful {

    private final Id contentVersionId;
    private final String sourceFileName;
    private final String importBatchId;

    // Set in start(), read in every execute() — requires Database.Stateful
    @TestVisible private List<String> headers;
    @TestVisible private CounterpointFileParser.DateVariant dateVariant;

    @TestVisible private Integer successCount = 0;
    @TestVisible private Integer errorCount   = 0;

    public CounterpointIngestionBatch(Id contentVersionId, String sourceFileName) {
        this.contentVersionId = contentVersionId;
        this.sourceFileName   = sourceFileName;
        this.importBatchId    = String.valueOf(DateTime.now().getTime());
    }

    // ─── Batchable ───────────────────────────────────────────────────────────

    public Iterable<String> start(Database.BatchableContext bc) {
        ContentVersion cv = [
            SELECT VersionData
            FROM   ContentVersion
            WHERE  Id = :contentVersionId
            LIMIT  1
        ];

        String csvContent = cv.VersionData.toString();
        List<String> allLines = csvContent.split('\n');

        if (allLines.isEmpty()) return new List<String>();

        // Parse header and detect variant
        String headerLine = allLines[0].replace('\r', '');
        headers     = CounterpointFileParser.parseRow(headerLine);
        dateVariant = CounterpointFileParser.detectVariant(headers);

        // Return only non-blank data rows (skip header)
        List<String> dataRows = new List<String>();
        for (Integer i = 1; i < allLines.size(); i++) {
            if (String.isNotBlank(allLines[i].replace('\r', '').trim())) {
                dataRows.add(allLines[i]);
            }
        }
        return dataRows;
    }

    public void execute(Database.BatchableContext bc, List<String> rows) {
        // ── Step 1: parse all rows in this chunk ────────────────────────────
        Set<String>              stationCodes    = new Set<String>();
        Set<String>              vehicleCodes    = new Set<String>();
        Set<String>              advertiserNames = new Set<String>();
        List<Map<String, String>> rowMaps        = new List<Map<String, String>>();

        for (String row : rows) {
            String line = row.replace('\r', '').trim();
            if (String.isBlank(line)) continue;

            Map<String, String> rowMap = buildRowMap(
                headers,
                CounterpointFileParser.parseRow(line)
            );
            rowMaps.add(rowMap);

            String station    = rowMap.get('STATION');
            String vehicle    = rowMap.get('VEHICLE');
            String advertiser = rowMap.get('ADVERTISER');
            if (String.isNotBlank(station))    stationCodes.add(station);
            if (String.isNotBlank(vehicle))    vehicleCodes.add(vehicle);
            if (String.isNotBlank(advertiser)) advertiserNames.add(advertiser);
        }

        // ── Step 2: bulk lookups (3 SOQL per execute call) ──────────────────
        Map<String, Id> channelMap = new Map<String, Id>();
        for (Channel__c c : [
            SELECT Id, Channel_Code__c
            FROM   Channel__c
            WHERE  Channel_Code__c IN :stationCodes
        ]) {
            channelMap.put(c.Channel_Code__c, c.Id);
        }

        Map<String, Id> vehicleMap = new Map<String, Id>();
        for (Vehicle__c v : [
            SELECT Id, Vehicle_Code__c
            FROM   Vehicle__c
            WHERE  Vehicle_Code__c IN :vehicleCodes
        ]) {
            vehicleMap.put(v.Vehicle_Code__c, v.Id);
        }

        Map<String, Id> accountMap = new Map<String, Id>();
        for (Account a : [
            SELECT Id, Name
            FROM   Account
            WHERE  Name IN :advertiserNames
        ]) {
            // First match wins on duplicate names
            if (!accountMap.containsKey(a.Name)) {
                accountMap.put(a.Name, a.Id);
            }
        }

        // ── Step 3: build Actuals_Record__c records ──────────────────────────
        List<Actuals_Record__c> toUpsert = new List<Actuals_Record__c>();
        for (Map<String, String> rowMap : rowMaps) {
            Actuals_Record__c rec = buildRecord(rowMap, channelMap, vehicleMap, accountMap);
            if (rec != null) toUpsert.add(rec);
        }

        // ── Step 4: upsert keyed on external ID (idempotent) ─────────────────
        if (!toUpsert.isEmpty()) {
            List<Database.UpsertResult> results = Database.upsert(
                toUpsert,
                Actuals_Record__c.Counterpoint_Order_ID__c,
                false
            );
            for (Database.UpsertResult r : results) {
                if (r.isSuccess()) {
                    successCount++;
                } else {
                    errorCount++;
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'CounterpointIngestionBatch complete — file: ' + sourceFileName +
            ', success: ' + successCount + ', errors: ' + errorCount
        );
    }

    // ─── Private helpers ─────────────────────────────────────────────────────

    private Map<String, String> buildRowMap(List<String> hdrs, List<String> values) {
        Map<String, String> rowMap = new Map<String, String>();
        for (Integer j = 0; j < hdrs.size() && j < values.size(); j++) {
            rowMap.put(CounterpointFileParser.normalizeKey(hdrs[j]), values[j]);
        }
        return rowMap;
    }

    private Actuals_Record__c buildRecord(
        Map<String, String> row,
        Map<String, Id>     channelMap,
        Map<String, Id>     vehicleMap,
        Map<String, Id>     accountMap
    ) {
        String orderId = row.get('ORDER_ID');
        if (String.isBlank(orderId)) return null;

        Actuals_Record__c rec = new Actuals_Record__c();
        rec.Counterpoint_Order_ID__c = orderId;
        rec.Market__c                = row.get('MARKET');
        rec.Subcategory__c           = row.get('SUBCATEGORY');
        rec.Station_Code__c          = row.get('STATION');
        rec.Station__c               = channelMap.get(row.get('STATION'));
        rec.Advertiser_Name__c       = row.get('ADVERTISER');
        rec.Advertiser__c            = accountMap.get(row.get('ADVERTISER'));
        rec.Vehicle_Code__c          = row.get('VEHICLE');
        rec.Vehicle__c               = vehicleMap.get(row.get('VEHICLE'));
        rec.Gross_Revenue__c         = CounterpointFileParser.parseDecimal(row.get('GROSS_REVENUE'));
        rec.Net_Revenue__c           = CounterpointFileParser.parseDecimal(row.get('NET_REVENUE'));
        rec.Source_File__c           = sourceFileName;
        rec.Import_Batch_ID__c       = importBatchId;

        // Agency commission: use explicit column if present, otherwise derive
        if (row.containsKey('AGENCY_COMMISSION') && String.isNotBlank(row.get('AGENCY_COMMISSION'))) {
            rec.Agency_Commission__c = CounterpointFileParser.parseDecimal(row.get('AGENCY_COMMISSION'));
        } else {
            rec.Agency_Commission__c = rec.Gross_Revenue__c - rec.Net_Revenue__c;
        }

        // Date fields
        rec.Date_Type__c = dateVariant == CounterpointFileParser.DateVariant.CALENDAR
            ? 'Calendar'
            : 'Broadcast';

        if (dateVariant == CounterpointFileParser.DateVariant.CALENDAR) {
            String dateVal = row.containsKey('CALENDAR_DATE')
                ? row.get('CALENDAR_DATE')
                : row.get('AIR_DATE');
            rec.Calendar_Date__c = CounterpointFileParser.parseDate(dateVal);
        } else {
            String dateVal = row.containsKey('BROADCAST_DATE')
                ? row.get('BROADCAST_DATE')
                : row.get('BCAST_DATE');
            rec.Broadcast_Date__c = CounterpointFileParser.parseDate(dateVal);
        }

        // Match status
        Boolean fullyMatched = rec.Station__c != null
            && rec.Vehicle__c   != null
            && rec.Advertiser__c != null;
        rec.Status__c = fullyMatched ? 'Matched' : 'Unmatched';

        if (!fullyMatched) {
            List<String> misses = new List<String>();
            if (rec.Station__c    == null && String.isNotBlank(rec.Station_Code__c))
                misses.add('Station not found: '    + rec.Station_Code__c);
            if (rec.Vehicle__c    == null && String.isNotBlank(rec.Vehicle_Code__c))
                misses.add('Vehicle not found: '    + rec.Vehicle_Code__c);
            if (rec.Advertiser__c == null && String.isNotBlank(rec.Advertiser_Name__c))
                misses.add('Advertiser not found: ' + rec.Advertiser_Name__c);
            if (!misses.isEmpty()) rec.Match_Notes__c = String.join(misses, '; ');
        }

        return rec;
    }
}
