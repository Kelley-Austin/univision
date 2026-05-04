/**
 * Static utility for parsing Counterpoint sales order CSV exports.
 *
 * Two file variants are supported, detected from the header row:
 *   Calendar variant  — contains a "Calendar_Date" or "Air_Date" column
 *   Broadcast variant — contains a "Broadcast_Date" or "Bcast_Date" column
 *
 * Expected columns (order-independent, case-insensitive):
 *   Market, Subcategory, Station, Advertiser, Vehicle,
 *   Calendar_Date | Air_Date  -OR-  Broadcast_Date | Bcast_Date,
 *   Gross_Revenue, Net_Revenue, [Agency_Commission], Order_ID
 */
public class CounterpointFileParser {

    public enum DateVariant { CALENDAR, BROADCAST }

    // ─── Public API ──────────────────────────────────────────────────────────

    public static DateVariant detectVariant(List<String> headers) {
        for (String h : headers) {
            String key = normalizeKey(h);
            if (key == 'BROADCAST_DATE' || key == 'BCAST_DATE') {
                return DateVariant.BROADCAST;
            }
        }
        for (String h : headers) {
            String key = normalizeKey(h);
            if (key == 'CALENDAR_DATE' || key == 'AIR_DATE' || key == 'DATE') {
                return DateVariant.CALENDAR;
            }
        }
        throw new ParseException(
            'Cannot detect date variant. Header must contain Calendar_Date/Air_Date (calendar) ' +
            'or Broadcast_Date/Bcast_Date (broadcast). Found: ' + String.join(headers, ', ')
        );
    }

    /**
     * Splits one CSV line into fields, handling RFC-4180 double-quoted values
     * (commas inside quotes, escaped quotes as "").
     */
    public static List<String> parseRow(String line) {
        List<String> values = new List<String>();
        Boolean inQuotes = false;
        String current = '';

        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                // Escaped quote inside quoted field ("" → ")
                if (inQuotes && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    current += '"';
                    i++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (ch == ',' && !inQuotes) {
                values.add(current.trim());
                current = '';
            } else {
                current += ch;
            }
        }
        values.add(current.trim());
        return values;
    }

    /** Strips currency formatting ($, commas) and converts to Decimal. Returns 0 on blank/invalid. */
    public static Decimal parseDecimal(String val) {
        if (String.isBlank(val)) return 0;
        String cleaned = val.replace('$', '').replace(',', '').trim();
        try {
            return Decimal.valueOf(cleaned);
        } catch (Exception e) {
            return 0;
        }
    }

    /**
     * Parses a date string in MM/DD/YYYY or YYYY-MM-DD format.
     * Returns null on blank input or parse failure.
     */
    public static Date parseDate(String val) {
        if (String.isBlank(val)) return null;
        String trimmed = val.trim();
        try {
            if (trimmed.contains('/')) {
                List<String> parts = trimmed.split('/');
                if (parts.size() == 3) {
                    return Date.newInstance(
                        Integer.valueOf(parts[2]),
                        Integer.valueOf(parts[0]),
                        Integer.valueOf(parts[1])
                    );
                }
            }
            return Date.valueOf(trimmed);
        } catch (Exception e) {
            return null;
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /** Normalizes a header token to upper-case with spaces replaced by underscores. */
    public static String normalizeKey(String raw) {
        return raw == null ? '' : raw.toUpperCase().replace(' ', '_').trim();
    }

    public class ParseException extends Exception {}
}
