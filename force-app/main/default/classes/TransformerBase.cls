/**
 * Shared utilities for all ITransformer implementations.
 * Keeps transformer classes lean and consistent.
 */
public virtual class TransformerBase {

    // ── Encoding helpers ──────────────────────────────────────────────────

    /**
     * Decode a UTF-16 Blob that may begin with a byte-order mark (BOM).
     * Salesforce Blob.toString() assumes UTF-8; this method handles the
     * BOM stripping and re-encodes the content as a UTF-8 string for CSV parsing.
     */
    protected String decodeUtf16(Blob fileContent) {
        String hex = EncodingUtil.convertToHex(fileContent).toUpperCase();
        // Strip BOM (FEFF = big-endian UTF-16, FFFE = little-endian UTF-16)
        if (hex.startsWith('FEFF') || hex.startsWith('FFFE')) {
            hex = hex.substring(4);
        }
        // Convert UTF-16 hex pairs → character list (big-endian assumed after BOM strip)
        String result = '';
        for (Integer i = 0; i < hex.length(); i += 4) {
            String charHex = hex.substring(i, i + 4);
            Integer codePoint = Integer.valueOf('0x' + charHex);
            if (codePoint == 0x000D || codePoint == 0x000A || (codePoint >= 0x0020 && codePoint <= 0x007E)) {
                result += String.fromCharArray(new List<Integer>{ codePoint });
            } else if (codePoint > 0x007E) {
                // Preserve extended Latin as-is for display (stored in Raw_Record__c)
                result += String.fromCharArray(new List<Integer>{ codePoint });
            }
        }
        return result;
    }

    /**
     * Decode CP1252 (Windows-1252) Blob to String.
     * Salesforce natively supports UTF-8; CP1252 bytes 0x80–0x9F map to
     * specific Unicode code points that differ from Latin-1.
     * This method substitutes the handful of CP1252-specific characters
     * that appear in typical advertising data (en-dash, em-dash, smart quotes).
     */
    protected String decodeCp1252(Blob fileContent) {
        String raw = fileContent.toString(); // treat as Latin-1 best-effort
        // Substitute common CP1252 non-Latin-1 bytes that survive toString()
        raw = raw.replace('', '€'); // Euro sign
        raw = raw.replace('', '…'); // Horizontal ellipsis
        raw = raw.replace('', '‘'); // Left single quotation
        raw = raw.replace('', '’'); // Right single quotation
        raw = raw.replace('', '“'); // Left double quotation
        raw = raw.replace('', '”'); // Right double quotation
        raw = raw.replace('', '–'); // En dash
        raw = raw.replace('', '—'); // Em dash
        return raw;
    }

    // ── CSV / TSV parsing ─────────────────────────────────────────────────

    /**
     * Split a delimited line respecting RFC-4180 quoting.
     * Works for both comma and tab delimiters.
     */
    protected List<String> parseLine(String line, String delimiter) {
        List<String> fields = new List<String>();
        if (String.isBlank(line)) return fields;

        Boolean inQuote = false;
        String current = '';
        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                if (inQuote && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    current += '"';
                    i++;
                } else {
                    inQuote = !inQuote;
                }
            } else if (ch == delimiter && !inQuote) {
                fields.add(current.trim());
                current = '';
            } else {
                current += ch;
            }
        }
        fields.add(current.trim());
        return fields;
    }

    /**
     * Build a header→index map from the first row of parsed columns (case-insensitive).
     */
    protected Map<String, Integer> buildHeaderMap(List<String> headers) {
        Map<String, Integer> map = new Map<String, Integer>();
        for (Integer i = 0; i < headers.size(); i++) {
            map.put(headers[i].trim().toLowerCase(), i);
        }
        return map;
    }

    /**
     * Safe get: returns '' if index out of range or list is null.
     */
    protected String safeGet(List<String> cols, Integer idx) {
        if (cols == null || idx == null || idx < 0 || idx >= cols.size()) return '';
        String val = cols[idx];
        return val == null ? '' : val.trim();
    }

    /**
     * Parse a currency string ('$1,234.56' or '1234.56') to Decimal. Returns null on failure.
     */
    protected Decimal parseCurrency(String raw) {
        if (String.isBlank(raw)) return null;
        String cleaned = raw.replaceAll('[^\\d.\\-]', '');
        try {
            return Decimal.valueOf(cleaned);
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * Build a deterministic External_Key from source code + row fingerprint (SHA-256 hex).
     * Using a hash keeps the key within 255 chars even for very long rows.
     */
    protected String buildExternalKey(String sourceCode, String rowData) {
        Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(sourceCode + '::' + rowData));
        return sourceCode + '_' + EncodingUtil.convertToHex(hash).substring(0, 40);
    }

    /**
     * Factory: return the ITransformer instance for the given Source_System__c config.
     * Throws IngestException if the class does not exist or does not implement ITransformer.
     */
    public static ITransformer forSourceSystem(Source_System__c config) {
        if (config == null || String.isBlank(config.Transformer_Class__c)) {
            throw new IngestService.IngestException('Source_System__c config is missing Transformer_Class__c.');
        }
        Type t = Type.forName(config.Transformer_Class__c);
        if (t == null) {
            throw new IngestService.IngestException(
                'Transformer class not found: ' + config.Transformer_Class__c
            );
        }
        Object instance = t.newInstance();
        if (!(instance instanceof ITransformer)) {
            throw new IngestService.IngestException(
                config.Transformer_Class__c + ' does not implement ITransformer.'
            );
        }
        return (ITransformer) instance;
    }
}
