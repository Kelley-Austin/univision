/**
 * =============================================================================
 *  Logger — Application logging framework for the Univision Salesforce project
 * =============================================================================
 *
 *  Why we have a Logger
 *  --------------------
 *  System.debug() output is ephemeral — it lives in the debug log, which is
 *  capped per user, capped per session, and gone when the session is. For
 *  production troubleshooting we need persistent, queryable, reportable
 *  records of WARN / ERROR / CRITICAL events. The Logger writes structured
 *  rows to Log__c so:
 *    * Operators can build list views and reports for "errors today by class".
 *    * Incident analysts can navigate from a Log__c entry to the Related
 *      Record via Related_Record_Id__c.
 *    * Stack traces from caught exceptions are captured at the point of
 *      handling, not lost.
 *
 *  Usage
 *  -----
 *      Logger.error('IngestService.parseFile', 'Could not parse row', ex);
 *      Logger.warn('AccountMatcher.matchTier3',  'Fuzzy match below threshold', accountId);
 *      Logger.info('PeriodCloseService.close',   'Closing period ' + year + '/' + month);
 *      // ... at the end of the request / queueable / invocable:
 *      Logger.flush();
 *
 *  Buffering and flush
 *  -------------------
 *  Logger.<level>() does NOT do DML on every call. It appends a Log__c to a
 *  static buffer. flush() does the DML in one Database.insert. Reasons:
 *    * Trigger handlers may emit several log entries; one DML per trigger
 *      execution is dramatically cheaper than one per log line.
 *    * Buffer + flush integrates cleanly with try/finally for
 *      exception-resilient logging.
 *
 *  Auto-flush threshold
 *  --------------------
 *  If the buffer crosses MAX_BUFFERED, flush() is called automatically to
 *  prevent heap pressure in long-running queueables. Callers should still
 *  call flush() explicitly at the end of the unit of work for completeness.
 *
 *  Test gating
 *  -----------
 *  Tests should NOT pollute the org with Log__c rows. By default, flush() is
 *  a no-op when Test.isRunningTest() is true. Tests that want to assert on
 *  log content set `suppressInTests = false` or use the @TestVisible
 *  `getBuffer()` helper to inspect the un-flushed buffer.
 *
 *  Source convention
 *  -----------------
 *  The first argument to every level method is the source string in the
 *  form "ClassName.methodName". Logger splits on the first dot to populate
 *  Source_Class__c and Source_Method__c separately, which makes filtering
 *  in list views much easier. If you log without a method, just pass the
 *  class name; Source_Method__c will be left null.
 *
 *  WARNING about partial inserts
 *  -----------------------------
 *  Database.insert(buffer, false) is used so a single bad log doesn't
 *  block the rest. If a Log__c insert fails (e.g. a runaway message busts a
 *  governor limit), the failure is itself System.debug()-ed — we cannot
 *  Logger.error() about a Logger failure without infinite recursion.
 * =============================================================================
 */
public with sharing class Logger {

    // ─── Severity level strings ───────────────────────────────────────────────
    // Mirror the picklist values on Log__c.Severity__c. Centralised as constants
    // so a typo is a compile error, not a silently-skipped picklist mismatch.
    public static final String SEV_DEBUG    = 'DEBUG';
    public static final String SEV_INFO     = 'INFO';
    public static final String SEV_WARN     = 'WARN';
    public static final String SEV_ERROR    = 'ERROR';
    public static final String SEV_CRITICAL = 'CRITICAL';

    // ─── Buffer ────────────────────────────────────────────────────────────────
    // Static across the transaction; reset between transactions automatically.
    @TestVisible
    private static List<Log__c> buffer = new List<Log__c>();

    // Auto-flush threshold. Picked to balance "don't blow heap" against "don't
    // spam DML"; revisit if heap pressure or DML count alarms fire in prod.
    @TestVisible
    private static final Integer MAX_BUFFERED = 100;

    // ─── Test seam ─────────────────────────────────────────────────────────────
    // When true (default), flush() does nothing under test context. Tests that
    // want to assert log content either flip this to false then call flush(),
    // or read the buffer directly via @TestVisible getBuffer().
    @TestVisible
    private static Boolean suppressInTests = true;

    // =========================================================================
    //  Public API — level methods
    // =========================================================================

    public static void debug(String source, String message) {
        record(SEV_DEBUG, source, message, null, null, null);
    }

    public static void info(String source, String message) {
        record(SEV_INFO, source, message, null, null, null);
    }

    public static void warn(String source, String message) {
        record(SEV_WARN, source, message, null, null, null);
    }

    public static void warn(String source, String message, Id relatedId) {
        record(SEV_WARN, source, message, null, relatedId, null);
    }

    public static void error(String source, String message) {
        record(SEV_ERROR, source, message, null, null, null);
    }

    public static void error(String source, String message, Exception ex) {
        record(SEV_ERROR, source, message, ex, null, null);
    }

    public static void error(String source, String message, Id relatedId, Exception ex) {
        record(SEV_ERROR, source, message, ex, relatedId, null);
    }

    public static void critical(String source, String message, Exception ex) {
        record(SEV_CRITICAL, source, message, ex, null, null);
    }

    public static void critical(String source, String message, Id relatedId, Exception ex) {
        record(SEV_CRITICAL, source, message, ex, relatedId, null);
    }

    /**
     * Generic shape for callers that want to attach arbitrary JSON context
     * (request parameters, intermediate variable values) to a log entry.
     */
    public static void log(String severity, String source, String message,
                           Exception ex, Id relatedId, String contextJson) {
        record(severity, source, message, ex, relatedId, contextJson);
    }

    // =========================================================================
    //  Flush
    // =========================================================================

    /**
     * Insert any buffered log entries and clear the buffer. Idempotent:
     * calling flush() with an empty buffer is a no-op. Skips DML in test
     * context unless suppressInTests has been flipped off by the test.
     */
    public static void flush() {
        if (buffer.isEmpty()) return;

        if (Test.isRunningTest() && suppressInTests) {
            // Don't pollute test org. Buffer remains for inspection by
            // tests that explicitly want to check what was logged.
            return;
        }

        // Partial-success: a single bad row should not lose the rest.
        // Errors get System.debug()-ed because we cannot Logger.error
        // about a Logger failure without infinite recursion.
        try {
            Database.SaveResult[] results =
                Database.insert(buffer, /* allOrNone */ false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    System.debug(LoggingLevel.ERROR,
                        'Logger.flush insert failure: ' +
                        results[i].getErrors()[0].getMessage());
                }
            }
        } catch (Exception ex) {
            // Defensive: any unexpected exception during flush gets a debug
            // line. Don't rethrow; logging shouldn't take down the host
            // transaction.
            System.debug(LoggingLevel.ERROR,
                'Logger.flush threw: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
        } finally {
            buffer.clear();
        }
    }

    /**
     * Convenience: clear the buffer without inserting. Use when an outer
     * exception handler decided to roll back and the partially-buffered
     * logs no longer apply.
     */
    public static void discard() {
        buffer.clear();
    }

    // =========================================================================
    //  Test introspection
    // =========================================================================

    /**
     * Return a defensive copy of the current buffer. Tests use this to assert
     * "did we emit a CRITICAL log for this scenario" without going through
     * DML and a SOQL.
     */
    @TestVisible
    private static List<Log__c> getBuffer() {
        return buffer.deepClone(false);
    }

    @TestVisible
    private static Integer bufferSize() {
        return buffer.size();
    }

    // =========================================================================
    //  Internals
    // =========================================================================

    /**
     * Build a Log__c row from the supplied arguments and append it to the
     * buffer. Triggers an auto-flush if MAX_BUFFERED would be exceeded.
     */
    private static void record(
        String severity,
        String source,
        String message,
        Exception ex,
        Id relatedId,
        String contextJson
    ) {
        Log__c entry = new Log__c();
        entry.Severity__c = severity;
        entry.Logged_At__c = Datetime.now();

        // Truncate to field length to avoid governor / metadata-validation
        // failures on monstrously large messages.
        if (message != null) {
            entry.Message__c = message.abbreviate(32768);
        }

        // Parse 'ClassName.methodName' into the two fields. Anything before
        // the FIRST dot is class; everything after is method. Falls back to
        // class only when no dot is present. Truncate each side.
        if (String.isNotBlank(source)) {
            Integer dotIdx = source.indexOf('.');
            if (dotIdx > 0) {
                entry.Source_Class__c  = source.substring(0, dotIdx).abbreviate(80);
                entry.Source_Method__c = source.substring(dotIdx + 1).abbreviate(80);
            } else {
                entry.Source_Class__c = source.abbreviate(80);
            }
        }

        if (relatedId != null) {
            // 18-character ID. String.valueOf(Id) returns the 18-char form.
            entry.Related_Record_Id__c = String.valueOf(relatedId);
        }

        if (ex != null) {
            // Append the exception's class + message to the human-readable
            // message so an operator can see "what happened" without opening
            // the trace, and capture the full trace separately.
            String exMsg = ex.getTypeName() + ': ' + ex.getMessage();
            entry.Message__c = entry.Message__c == null
                ? exMsg.abbreviate(32768)
                : (entry.Message__c + '\n' + exMsg).abbreviate(32768);
            entry.Stack_Trace__c = ex.getStackTraceString().abbreviate(32768);
        }

        if (contextJson != null) {
            entry.Context__c = contextJson.abbreviate(32768);
        }

        buffer.add(entry);

        // Auto-flush before heap pressure becomes a problem. The threshold is
        // soft — callers should still flush() explicitly at end of unit of work.
        if (buffer.size() >= MAX_BUFFERED) {
            flush();
        }
    }
}
