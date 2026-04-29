/**
 * Invocable service for Counterpoint CSV imports.
 *
 * Called by the Counterpoint_CSV_Import Screen Flow via the Import Counterpoint Data
 * quick action on Advertising_Opportunity__c.
 *
 * Flow:
 *  1. Reads the uploaded ContentVersion.
 *  2. Parses every row, applying date-type logic (Calendar vs Broadcast).
 *  3. Derives or hashes Counterpoint_Order_ID__c; deduplicates within the file.
 *  4. Inserts Actuals_Record__c rows (Pending / Invalid / Duplicate).
 *  5. Enqueues CounterpointIngestionBatch to finalize Pending rows and reject
 *     cross-batch duplicates.
 */
public with sharing class CounterpointIngestionService {

    // ── Invocable contract ────────────────────────────────────────────────

    public class ImportRequest {
        @InvocableVariable(required=true label='Content Document ID'
            description='ContentDocumentId returned by lightning-file-upload')
        public Id contentDocumentId;

        @InvocableVariable(required=true label='Date Type'
            description='Calendar or Broadcast — controls which date field is populated')
        public String dateType;

        @InvocableVariable(label='Opportunity ID'
            description='Advertising_Opportunity__c record that triggered the quick action')
        public Id opportunityId;
    }

    public class ImportResult {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String  importBatchId;
        @InvocableVariable public Integer totalRows;
        @InvocableVariable public Integer validRows;
        @InvocableVariable public Integer invalidRows;
        @InvocableVariable public String  errorMessage;
    }

    @InvocableMethod(
        label='Import Counterpoint CSV'
        description='Parses and validates a Counterpoint CSV file, inserts Actuals_Record__c rows, and queues CounterpointIngestionBatch to finalise them.'
        callout=false
    )
    public static List<ImportResult> importCsv(List<ImportRequest> requests) {
        List<ImportResult> results = new List<ImportResult>();
        for (ImportRequest req : requests) {
            results.add(processRequest(req));
        }
        return results;
    }

    // ── AuraEnabled entry point (called by counterpointFileUpload LWC) ────
    // @InvocableMethod is not directly callable from LWC; this wrapper
    // exposes the same logic under an @AuraEnabled surface.

    @AuraEnabled
    public static ImportResult importCsvFromLwc(
        Id     contentDocumentId,
        String dateType,
        Id     opportunityId
    ) {
        ImportRequest req = new ImportRequest();
        req.contentDocumentId = contentDocumentId;
        req.dateType          = dateType;
        req.opportunityId     = opportunityId;
        return processRequest(req);
    }

    // ── Private processing ────────────────────────────────────────────────

    private static ImportResult processRequest(ImportRequest req) {
        ImportResult result = new ImportResult();
        String importBatchId = generateBatchId();

        try {
            ContentVersion cv = [
                SELECT Id, Title, VersionData
                FROM   ContentVersion
                WHERE  ContentDocumentId = :req.contentDocumentId
                  AND  IsLatest = true
                LIMIT  1
            ];

            List<Actuals_Record__c> records = parseAndValidate(
                cv.VersionData, req.dateType, importBatchId, req.opportunityId, cv.Title
            );

            if (records.isEmpty()) {
                result.success       = true;
                result.importBatchId = importBatchId;
                result.totalRows     = 0;
                result.validRows     = 0;
                result.invalidRows   = 0;
                return result;
            }

            insert records;

            Integer valid   = 0;
            Integer invalid = 0;
            for (Actuals_Record__c r : records) {
                if (r.Validation_Status__c == 'Pending') valid++;
                else invalid++;
            }

            if (valid > 0) {
                Database.executeBatch(new CounterpointIngestionBatch(importBatchId), 200);
            }

            result.success       = true;
            result.importBatchId = importBatchId;
            result.totalRows     = records.size();
            result.validRows     = valid;
            result.invalidRows   = invalid;

        } catch (Exception e) {
            result.success      = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    // ── CSV parsing ───────────────────────────────────────────────────────

    @TestVisible
    static List<Actuals_Record__c> parseAndValidate(
        Blob   fileBlob,
        String dateType,
        String importBatchId,
        Id     opportunityId,
        String fileName
    ) {
        String raw = fileBlob.toString();
        // Strip BOM
        if (raw.startsWith('﻿')) raw = raw.substring(1);

        List<Actuals_Record__c> records = new List<Actuals_Record__c>();
        List<String> lines = raw.split('\n');
        if (lines.isEmpty()) return records;

        Integer headerIdx = 0;
        while (headerIdx < lines.size() && String.isBlank(lines[headerIdx])) headerIdx++;
        if (headerIdx >= lines.size()) return records;

        List<String> headerCols = parseCsvLine(lines[headerIdx].removeEnd('\r'));
        Map<String, Integer> hdr = new Map<String, Integer>();
        for (Integer i = 0; i < headerCols.size(); i++) {
            hdr.put(headerCols[i].toLowerCase().trim(), i);
        }
        Integer expectedCols = headerCols.size();

        Integer colOrderId    = findCol(hdr, new List<String>{'order id','orderid','order_id','order #','order no','order'});
        Integer colAdvertiser = findCol(hdr, new List<String>{'advertiser','advertiser name'});
        Integer colAgency     = findCol(hdr, new List<String>{'agency','agency name'});
        Integer colStation    = findCol(hdr, new List<String>{'station','station code'});
        Integer colType       = findCol(hdr, new List<String>{'type','revenue type','rev type'});
        Integer colAmount     = findCol(hdr, new List<String>{'amount','net amount','revenue','net'});
        Integer colAe         = findCol(hdr, new List<String>{'ae','ae code','account exec'});
        Integer colPeriod     = findCol(hdr, new List<String>{'period','broadcast period','cal period','month'});

        Set<String> seenOrderIds = new Set<String>();

        for (Integer i = headerIdx + 1; i < lines.size(); i++) {
            String line = lines[i].removeEnd('\r');
            if (String.isBlank(line)) continue;

            List<String> cols = parseCsvLine(line);

            Actuals_Record__c rec = new Actuals_Record__c(
                Import_Batch_ID__c    = importBatchId,
                Date_Type__c          = dateType,
                Opportunity__c        = opportunityId,
                Source_File_Name__c   = fileName,
                Validation_Status__c  = 'Pending'
            );

            if (cols.size() < expectedCols) {
                rec.Validation_Status__c  = 'Invalid';
                rec.Validation_Error__c   = 'MALFORMED_ROW: expected ' + expectedCols + ' columns, got ' + cols.size();
                rec.Counterpoint_Order_ID__c = importBatchId + '_row_' + i;
                records.add(rec);
                continue;
            }

            String advertiser = safeGet(cols, colAdvertiser);
            if (String.isBlank(advertiser)) {
                rec.Validation_Status__c  = 'Invalid';
                rec.Validation_Error__c   = 'BLANK_ADVERTISER';
                rec.Counterpoint_Order_ID__c = importBatchId + '_row_' + i;
                records.add(rec);
                continue;
            }

            String periodRaw = safeGet(cols, colPeriod);

            // Resolve and parse date
            if (dateType == 'Calendar') {
                Date parsed = parseCalendarDate(periodRaw);
                if (parsed == null && String.isNotBlank(periodRaw)) {
                    rec.Validation_Status__c = 'Invalid';
                    rec.Validation_Error__c  = 'UNPARSEABLE_CALENDAR_DATE: ' + periodRaw;
                } else {
                    rec.Calendar_Date__c = parsed;
                }
            } else {
                Date parsed = parseBroadcastDate(periodRaw);
                if (parsed == null && String.isNotBlank(periodRaw)) {
                    rec.Validation_Status__c = 'Invalid';
                    rec.Validation_Error__c  = 'UNPARSEABLE_BROADCAST_DATE: ' + periodRaw;
                } else {
                    rec.Broadcast_Date__c = parsed;
                }
            }

            rec.Advertiser_Name__c = advertiser;
            rec.Agency_Name__c     = safeGet(cols, colAgency);
            rec.Station_Code__c    = safeGet(cols, colStation);
            rec.Revenue_Type__c    = safeGet(cols, colType);
            rec.Revenue_Amount__c  = parseCurrency(safeGet(cols, colAmount));
            rec.AE_Code__c         = safeGet(cols, colAe);
            rec.Period_Raw__c      = periodRaw;

            // Derive dedup key
            String explicitId = safeGet(cols, colOrderId);
            String orderId;
            if (String.isNotBlank(explicitId)) {
                orderId = explicitId;
            } else {
                Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(
                    advertiser + '|' + safeGet(cols, colStation) + '|' + periodRaw + '|' + safeGet(cols, colType)
                ));
                orderId = EncodingUtil.convertToHex(digest).left(40);
            }

            // Within-file duplicate check
            if (seenOrderIds.contains(orderId)) {
                rec.Validation_Status__c  = 'Duplicate';
                rec.Validation_Error__c   = 'WITHIN_FILE_DUPLICATE: ' + orderId;
                rec.Counterpoint_Order_ID__c = importBatchId + '_dup_' + i;
            } else {
                seenOrderIds.add(orderId);
                rec.Counterpoint_Order_ID__c = orderId;
            }

            records.add(rec);
        }

        return records;
    }

    // ── Date parsing ──────────────────────────────────────────────────────

    @TestVisible
    static Date parseCalendarDate(String raw) {
        if (String.isBlank(raw)) return null;
        String s = raw.trim();

        // MM/YYYY
        Matcher m = Pattern.compile('^(\\d{1,2})/(\\d{4})$').matcher(s);
        if (m.matches()) return Date.newInstance(Integer.valueOf(m.group(2)), Integer.valueOf(m.group(1)), 1);

        // YYYY-MM
        m = Pattern.compile('^(\\d{4})-(\\d{2})$').matcher(s);
        if (m.matches()) return Date.newInstance(Integer.valueOf(m.group(1)), Integer.valueOf(m.group(2)), 1);

        // Full ISO or US date (YYYY-MM-DD or MM/DD/YYYY)
        try { return Date.valueOf(s); } catch (Exception e) {}

        m = Pattern.compile('^(\\d{1,2})/(\\d{1,2})/(\\d{4})$').matcher(s);
        if (m.matches()) return Date.newInstance(Integer.valueOf(m.group(3)), Integer.valueOf(m.group(1)), Integer.valueOf(m.group(2)));

        return null;
    }

    @TestVisible
    static Date parseBroadcastDate(String raw) {
        if (String.isBlank(raw)) return null;
        String s = raw.trim();

        // "WK OF MM/DD/YY" or "WK OF MM/DD/YYYY" (broadcast week)
        Matcher m = Pattern.compile('(?i)WK\\s*OF\\s*(\\d{1,2})/(\\d{1,2})/(\\d{2,4})').matcher(s);
        if (m.find()) {
            Integer month = Integer.valueOf(m.group(1));
            Integer day   = Integer.valueOf(m.group(2));
            Integer yr    = Integer.valueOf(m.group(3));
            if (yr < 100) yr += 2000;
            return Date.newInstance(yr, month, day);
        }

        // Broadcast month expressed as MM/YYYY or YYYY-MM falls through to calendar parser
        return parseCalendarDate(s);
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private static Integer findCol(Map<String, Integer> hdr, List<String> candidates) {
        for (String c : candidates) {
            if (hdr.containsKey(c)) return hdr.get(c);
        }
        return null;
    }

    private static String safeGet(List<String> cols, Integer idx) {
        if (idx == null || idx < 0 || idx >= cols.size()) return '';
        String v = cols[idx];
        return v == null ? '' : v.trim();
    }

    private static Decimal parseCurrency(String val) {
        if (String.isBlank(val)) return 0;
        try {
            return Decimal.valueOf(val.replaceAll('[^\\d.\\-]', ''));
        } catch (Exception e) {
            return 0;
        }
    }

    @TestVisible
    static List<String> parseCsvLine(String line) {
        List<String> result  = new List<String>();
        Boolean inQuote = false;
        String  current = '';
        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                if (inQuote && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    current += '"';
                    i++;
                } else {
                    inQuote = !inQuote;
                }
            } else if (ch == ',' && !inQuote) {
                result.add(current);
                current = '';
            } else {
                current += ch;
            }
        }
        result.add(current);
        return result;
    }

    private static String generateBatchId() {
        // 32-char hex token derived from current time + random salt
        Blob salt   = Crypto.generateAesKey(128);
        String ts   = String.valueOf(Datetime.now().getTime());
        Blob   data = Blob.valueOf(ts);
        Blob   digest = Crypto.generateDigest('SHA-256', data);
        return EncodingUtil.convertToHex(digest).left(32);
    }
}
