@IsTest
private class CounterpointIngestionServiceTest {

    // ── CSV helpers ───────────────────────────────────────────────────────

    private static Blob calendarCsv(String extra) {
        String csv = 'Order ID,Advertiser,Agency,Station,Type,Amount,AE,Period\n'
            + '1001,Acme Corp,Best Agency,KUVN,Local,50000.00,A1,01/2025\n'
            + '1002,Beta Inc,,WLTV,National,"25,000.50",B2,2025-02\n'
            + extra;
        return Blob.valueOf(csv);
    }

    private static Blob broadcastCsv() {
        String csv = 'Order ID,Advertiser,Agency,Station,Type,Amount,AE,Period\n'
            + '2001,Gamma LLC,,KVEA,Local,10000,C3,WK OF 01/06/2025\n'
            + '2002,Delta Co,,KUVN,National,5000,D4,02/2025\n';
        return Blob.valueOf(csv);
    }

    // ── parseAndValidate — calendar ───────────────────────────────────────

    @IsTest
    static void calendarRows_populateCalendarDate() {
        List<Actuals_Record__c> rows = CounterpointIngestionService.parseAndValidate(
            calendarCsv(''), 'Calendar', 'BATCH001', null, 'test.csv'
        );

        System.assertEquals(2, rows.size(), 'Expected 2 data rows');

        Actuals_Record__c row1 = rows[0];
        System.assertEquals('Pending',   row1.Validation_Status__c);
        System.assertEquals('1001',      row1.Counterpoint_Order_ID__c);
        System.assertEquals('Acme Corp', row1.Advertiser_Name__c);
        System.assertEquals('KUVN',      row1.Station_Code__c);
        System.assertEquals(Date.newInstance(2025, 1, 1), row1.Calendar_Date__c);
        System.assertEquals(null,        row1.Broadcast_Date__c, 'Broadcast date should be null for Calendar rows');

        Actuals_Record__c row2 = rows[1];
        System.assertEquals(Date.newInstance(2025, 2, 1), row2.Calendar_Date__c);
        System.assertEquals(Decimal.valueOf('25000.50'),  row2.Revenue_Amount__c);
    }

    // ── parseAndValidate — broadcast ──────────────────────────────────────

    @IsTest
    static void broadcastRows_populateBroadcastDate() {
        List<Actuals_Record__c> rows = CounterpointIngestionService.parseAndValidate(
            broadcastCsv(), 'Broadcast', 'BATCH002', null, 'bcast.csv'
        );

        System.assertEquals(2, rows.size());

        // Row 1: WK OF 01/06/2025
        System.assertEquals(Date.newInstance(2025, 1, 6), rows[0].Broadcast_Date__c);
        System.assertEquals(null, rows[0].Calendar_Date__c, 'Calendar date should be null for Broadcast rows');

        // Row 2: 02/2025 — broadcast month falls through to calendar-date parser
        System.assertEquals(Date.newInstance(2025, 2, 1), rows[1].Broadcast_Date__c);
    }

    // ── Within-file duplicate rejection ───────────────────────────────────

    @IsTest
    static void duplicateOrderId_markedDuplicateInService() {
        // Two rows with same Order ID in the same file
        String dupCsv = 'Order ID,Advertiser,Agency,Station,Type,Amount,AE,Period\n'
            + '9001,Acme Corp,,KUVN,Local,1000,A1,01/2025\n'
            + '9001,Acme Corp,,KUVN,Local,2000,A1,01/2025\n';

        List<Actuals_Record__c> rows = CounterpointIngestionService.parseAndValidate(
            Blob.valueOf(dupCsv), 'Calendar', 'BATCH003', null, 'dup.csv'
        );

        System.assertEquals(2, rows.size());
        System.assertEquals('Pending',   rows[0].Validation_Status__c);
        System.assertEquals('Duplicate', rows[1].Validation_Status__c);
        System.assert(rows[1].Validation_Error__c.contains('WITHIN_FILE_DUPLICATE'), 'Error should indicate within-file duplicate');
    }

    // ── Malformed / blank-advertiser rows ─────────────────────────────────

    @IsTest
    static void malformedRow_markedInvalid() {
        String bad = 'Order ID,Advertiser,Agency,Station,Type,Amount,AE,Period\n'
            + 'TOOFEWCOLS\n';
        List<Actuals_Record__c> rows = CounterpointIngestionService.parseAndValidate(
            Blob.valueOf(bad), 'Calendar', 'BATCH004', null, 'bad.csv'
        );
        System.assertEquals(1, rows.size());
        System.assertEquals('Invalid', rows[0].Validation_Status__c);
        System.assert(rows[0].Validation_Error__c.contains('MALFORMED_ROW'));
    }

    @IsTest
    static void blankAdvertiser_markedInvalid() {
        String bad = 'Order ID,Advertiser,Agency,Station,Type,Amount,AE,Period\n'
            + '3001,,Best Agency,KUVN,Local,1000,A1,01/2025\n';
        List<Actuals_Record__c> rows = CounterpointIngestionService.parseAndValidate(
            Blob.valueOf(bad), 'Calendar', 'BATCH005', null, 'bad.csv'
        );
        System.assertEquals(1, rows.size());
        System.assertEquals('Invalid', rows[0].Validation_Status__c);
        System.assertEquals('BLANK_ADVERTISER', rows[0].Validation_Error__c);
    }

    // ── Date parsing helpers ──────────────────────────────────────────────

    @IsTest
    static void parseCalendarDate_formats() {
        System.assertEquals(Date.newInstance(2025, 3, 1),  CounterpointIngestionService.parseCalendarDate('03/2025'));
        System.assertEquals(Date.newInstance(2025, 3, 1),  CounterpointIngestionService.parseCalendarDate('2025-03'));
        System.assertEquals(Date.newInstance(2025, 3, 15), CounterpointIngestionService.parseCalendarDate('2025-03-15'));
        System.assertEquals(Date.newInstance(2025, 3, 15), CounterpointIngestionService.parseCalendarDate('03/15/2025'));
        System.assertEquals(null, CounterpointIngestionService.parseCalendarDate('not-a-date'));
        System.assertEquals(null, CounterpointIngestionService.parseCalendarDate(''));
        System.assertEquals(null, CounterpointIngestionService.parseCalendarDate(null));
    }

    @IsTest
    static void parseBroadcastDate_wkOfFormat() {
        System.assertEquals(Date.newInstance(2025, 1, 6),  CounterpointIngestionService.parseBroadcastDate('WK OF 01/06/2025'));
        System.assertEquals(Date.newInstance(2025, 1, 6),  CounterpointIngestionService.parseBroadcastDate('wk of 01/06/25'));
        System.assertEquals(Date.newInstance(2025, 4, 1),  CounterpointIngestionService.parseBroadcastDate('04/2025'));
        System.assertEquals(null, CounterpointIngestionService.parseBroadcastDate(null));
    }

    // ── CSV quoted-field parsing ──────────────────────────────────────────

    @IsTest
    static void parseCsvLine_handlesQuotedCommas() {
        List<String> cols = CounterpointIngestionService.parseCsvLine('"Smith, John",Agency A,KUVN,"50,000",AE1');
        System.assertEquals(5, cols.size());
        System.assertEquals('Smith, John', cols[0]);
        System.assertEquals('50,000',      cols[3]);
    }

    @IsTest
    static void parseCsvLine_handlesEscapedQuotes() {
        List<String> cols = CounterpointIngestionService.parseCsvLine('"He said ""hello""",col2');
        System.assertEquals(2, cols.size());
        System.assertEquals('He said "hello"', cols[0]);
    }

    // ── End-to-end: importCsv invocable (mock insert + batch) ────────────

    @IsTest
    static void importCsv_emptyFile_returnsSuccessZeroRows() {
        // Build a minimal ContentDocument in a test context
        ContentVersion cv = new ContentVersion(
            Title          = 'empty.csv',
            VersionData    = Blob.valueOf(''),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        CounterpointIngestionService.ImportRequest req = new CounterpointIngestionService.ImportRequest();
        req.contentDocumentId = docId;
        req.dateType          = 'Calendar';

        Test.startTest();
        List<CounterpointIngestionService.ImportResult> results =
            CounterpointIngestionService.importCsv(new List<CounterpointIngestionService.ImportRequest>{req});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].success, 'Empty file should succeed with 0 rows');
        System.assertEquals(0, results[0].totalRows);
    }

    @IsTest
    static void importCsv_validRows_insertsRecordsAndQueuesBatch() {
        ContentVersion cv = new ContentVersion(
            Title          = 'actuals.csv',
            VersionData    = calendarCsv(''),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        CounterpointIngestionService.ImportRequest req = new CounterpointIngestionService.ImportRequest();
        req.contentDocumentId = docId;
        req.dateType          = 'Calendar';

        Test.startTest();
        List<CounterpointIngestionService.ImportResult> results =
            CounterpointIngestionService.importCsv(new List<CounterpointIngestionService.ImportRequest>{req});
        Test.stopTest();

        System.assertEquals(1, results.size());
        CounterpointIngestionService.ImportResult r = results[0];
        System.assert(r.success, r.errorMessage);
        System.assertEquals(2, r.totalRows);
        System.assertEquals(2, r.validRows);
        System.assertEquals(0, r.invalidRows);

        List<Actuals_Record__c> inserted = [SELECT Validation_Status__c, Calendar_Date__c FROM Actuals_Record__c WHERE Import_Batch_ID__c = :r.importBatchId];
        System.assertEquals(2, inserted.size(), 'Both rows should be inserted');
        for (Actuals_Record__c a : inserted) {
            System.assertEquals('Processed', a.Validation_Status__c, 'Batch should have promoted row to Processed');
            System.assertNotEquals(null, a.Calendar_Date__c, 'Calendar date must be set');
        }
    }

    // ── @AuraEnabled LWC entry point ──────────────────────────────────────

    @IsTest
    static void importCsvFromLwc_validFile_returnsSuccessResult() {
        ContentVersion cv = new ContentVersion(
            Title          = 'lwc_test.csv',
            VersionData    = calendarCsv(''),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        Test.startTest();
        CounterpointIngestionService.ImportResult r =
            CounterpointIngestionService.importCsvFromLwc(docId, 'Calendar', null);
        Test.stopTest();

        System.assert(r.success, r.errorMessage);
        System.assertEquals(2, r.totalRows);
        System.assertEquals(2, r.validRows);
        System.assertEquals(0, r.invalidRows);
        System.assertNotEquals(null, r.importBatchId, 'Batch ID must be stamped');
    }

    @IsTest
    static void importCsvFromLwc_broadcastFile_populatesBroadcastDate() {
        ContentVersion cv = new ContentVersion(
            Title          = 'bcast_lwc.csv',
            VersionData    = broadcastCsv(),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        Test.startTest();
        CounterpointIngestionService.ImportResult r =
            CounterpointIngestionService.importCsvFromLwc(docId, 'Broadcast', null);
        Test.stopTest();

        System.assert(r.success, r.errorMessage);
        List<Actuals_Record__c> rows = [
            SELECT Broadcast_Date__c, Calendar_Date__c
            FROM   Actuals_Record__c
            WHERE  Import_Batch_ID__c = :r.importBatchId
        ];
        System.assertEquals(2, rows.size());
        for (Actuals_Record__c row : rows) {
            System.assertNotEquals(null, row.Broadcast_Date__c, 'Broadcast date must be populated');
            System.assertEquals(null, row.Calendar_Date__c, 'Calendar date must be null for Broadcast rows');
        }
    }

    // ── Cross-batch duplicate rejection (batch test) ──────────────────────

    @IsTest
    static void batch_crossBatchDuplicate_markedDuplicate() {
        // Insert a "previously processed" record
        Actuals_Record__c prior = new Actuals_Record__c(
            Counterpoint_Order_ID__c = 'ORDER-PREV-001',
            Import_Batch_ID__c       = 'PRIOR_BATCH',
            Validation_Status__c     = 'Processed',
            Advertiser_Name__c       = 'Acme Corp'
        );
        insert prior;

        // New batch row with the same order ID
        Actuals_Record__c incoming = new Actuals_Record__c(
            Counterpoint_Order_ID__c = 'ORDER-PREV-001',
            Import_Batch_ID__c       = 'NEW_BATCH',
            Validation_Status__c     = 'Pending',
            Advertiser_Name__c       = 'Acme Corp'
        );
        insert incoming;

        Test.startTest();
        Database.executeBatch(new CounterpointIngestionBatch('NEW_BATCH'), 200);
        Test.stopTest();

        Actuals_Record__c updated = [SELECT Validation_Status__c, Validation_Error__c FROM Actuals_Record__c WHERE Id = :incoming.Id];
        System.assertEquals('Duplicate', updated.Validation_Status__c, 'Cross-batch duplicate should be rejected');
        System.assert(updated.Validation_Error__c.contains('CROSS_BATCH_DUPLICATE'));
    }
}
