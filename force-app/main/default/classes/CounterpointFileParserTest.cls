@isTest
private class CounterpointFileParserTest {

    // ─── detectVariant ────────────────────────────────────────────────────────

    @isTest
    static void detectVariant_calendarDate() {
        List<String> headers = new List<String>{ 'Market', 'Calendar_Date', 'Order_ID' };
        System.assertEquals(
            CounterpointFileParser.DateVariant.CALENDAR,
            CounterpointFileParser.detectVariant(headers)
        );
    }

    @isTest
    static void detectVariant_airDateAlias() {
        List<String> headers = new List<String>{ 'Market', 'Air_Date', 'Order_ID' };
        System.assertEquals(
            CounterpointFileParser.DateVariant.CALENDAR,
            CounterpointFileParser.detectVariant(headers)
        );
    }

    @isTest
    static void detectVariant_broadcastDate() {
        List<String> headers = new List<String>{ 'Market', 'Broadcast_Date', 'Order_ID' };
        System.assertEquals(
            CounterpointFileParser.DateVariant.BROADCAST,
            CounterpointFileParser.detectVariant(headers)
        );
    }

    @isTest
    static void detectVariant_bcastDateAlias() {
        List<String> headers = new List<String>{ 'Market', 'Bcast_Date', 'Order_ID' };
        System.assertEquals(
            CounterpointFileParser.DateVariant.BROADCAST,
            CounterpointFileParser.detectVariant(headers)
        );
    }

    @isTest
    static void detectVariant_broadcastTakesPrecedenceOverCalendar() {
        // If both appear (edge case), broadcast wins
        List<String> headers = new List<String>{ 'Calendar_Date', 'Broadcast_Date' };
        System.assertEquals(
            CounterpointFileParser.DateVariant.BROADCAST,
            CounterpointFileParser.detectVariant(headers)
        );
    }

    @isTest
    static void detectVariant_unknownHeaders_throwsException() {
        List<String> headers = new List<String>{ 'Market', 'Station', 'Revenue' };
        try {
            CounterpointFileParser.detectVariant(headers);
            System.assert(false, 'Expected ParseException');
        } catch (CounterpointFileParser.ParseException e) {
            System.assert(e.getMessage().contains('Cannot detect date variant'));
        }
    }

    // ─── parseRow ─────────────────────────────────────────────────────────────

    @isTest
    static void parseRow_simpleLine() {
        List<String> cols = CounterpointFileParser.parseRow('Miami,TV Spot,WFUU,Acme,BMF');
        System.assertEquals(5, cols.size());
        System.assertEquals('Miami', cols[0]);
        System.assertEquals('BMF',   cols[4]);
    }

    @isTest
    static void parseRow_quotedFieldWithComma() {
        List<String> cols = CounterpointFileParser.parseRow('"Miami, FL",TV Spot,WFUU');
        System.assertEquals(3, cols.size());
        System.assertEquals('Miami, FL', cols[0]);
    }

    @isTest
    static void parseRow_escapedQuoteInsideQuotedField() {
        List<String> cols = CounterpointFileParser.parseRow('"He said ""hello""",next');
        System.assertEquals(2, cols.size());
        System.assertEquals('He said "hello"', cols[0]);
    }

    @isTest
    static void parseRow_currencyFormattedNumber() {
        List<String> cols = CounterpointFileParser.parseRow('Miami,Spot,WFUU,"$1,000.00"');
        System.assertEquals(4, cols.size());
        System.assertEquals('$1,000.00', cols[3]);
    }

    @isTest
    static void parseRow_emptyFields() {
        List<String> cols = CounterpointFileParser.parseRow('Miami,,WFUU,,');
        System.assertEquals(5, cols.size());
        System.assertEquals('', cols[1]);
        System.assertEquals('', cols[3]);
    }

    // ─── parseDecimal ─────────────────────────────────────────────────────────

    @isTest
    static void parseDecimal_plainNumber() {
        System.assertEquals(1234.56, CounterpointFileParser.parseDecimal('1234.56'));
    }

    @isTest
    static void parseDecimal_currencyFormatted() {
        System.assertEquals(1000.00, CounterpointFileParser.parseDecimal('$1,000.00'));
    }

    @isTest
    static void parseDecimal_blankReturnsZero() {
        System.assertEquals(0, CounterpointFileParser.parseDecimal(''));
        System.assertEquals(0, CounterpointFileParser.parseDecimal(null));
    }

    @isTest
    static void parseDecimal_invalidReturnsZero() {
        System.assertEquals(0, CounterpointFileParser.parseDecimal('N/A'));
    }

    @isTest
    static void parseDecimal_negativeNumber() {
        System.assertEquals(-500.00, CounterpointFileParser.parseDecimal('-500.00'));
    }

    // ─── parseDate ────────────────────────────────────────────────────────────

    @isTest
    static void parseDate_mmDdYyyy() {
        Date d = CounterpointFileParser.parseDate('01/15/2025');
        System.assertEquals(Date.newInstance(2025, 1, 15), d);
    }

    @isTest
    static void parseDate_yyyyMmDd() {
        Date d = CounterpointFileParser.parseDate('2025-03-10');
        System.assertEquals(Date.newInstance(2025, 3, 10), d);
    }

    @isTest
    static void parseDate_blankReturnsNull() {
        System.assertEquals(null, CounterpointFileParser.parseDate(''));
        System.assertEquals(null, CounterpointFileParser.parseDate(null));
    }

    @isTest
    static void parseDate_invalidReturnsNull() {
        System.assertEquals(null, CounterpointFileParser.parseDate('not-a-date'));
    }

    // ─── normalizeKey ─────────────────────────────────────────────────────────

    @isTest
    static void normalizeKey_lowercaseWithSpaces() {
        System.assertEquals('GROSS_REVENUE', CounterpointFileParser.normalizeKey('Gross Revenue'));
    }

    @isTest
    static void normalizeKey_nullReturnsEmpty() {
        System.assertEquals('', CounterpointFileParser.normalizeKey(null));
    }
}
