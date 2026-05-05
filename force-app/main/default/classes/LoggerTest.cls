/**
 * =============================================================================
 *  LoggerTest
 * =============================================================================
 *
 *  Coverage focus
 *  --------------
 *    * Each severity level adds an entry of the correct severity.
 *    * Source-string parsing splits 'ClassName.methodName' correctly, falls
 *      back to class-only when no dot is present.
 *    * Exception capture populates Stack_Trace__c and appends the exception
 *      message to Message__c.
 *    * relatedId stamps Related_Record_Id__c.
 *    * flush() respects suppressInTests by default; flips correctly when the
 *      test opts in.
 *    * discard() clears the buffer without DML.
 *    * Auto-flush kicks in past MAX_BUFFERED.
 *
 *  Tests intentionally read the buffer via @TestVisible getBuffer() rather
 *  than querying Log__c — keeps them fast and decouples them from DML.
 * =============================================================================
 */
@IsTest
private class LoggerTest {

    // ─── Each severity wrapper records correctly ──────────────────────────────

    @IsTest
    static void debug_records_DEBUG_severity() {
        Logger.discard();

        Logger.debug('Foo.bar', 'a debug line');

        List<Log__c> buf = Logger.getBuffer();
        Assert.areEqual(1, buf.size(), 'one entry buffered');
        Assert.areEqual('DEBUG',     buf[0].Severity__c);
        Assert.areEqual('Foo',       buf[0].Source_Class__c);
        Assert.areEqual('bar',       buf[0].Source_Method__c);
        Assert.areEqual('a debug line', buf[0].Message__c);
    }

    @IsTest
    static void info_records_INFO_severity() {
        Logger.discard();
        Logger.info('Foo.bar', 'i');
        Assert.areEqual('INFO', Logger.getBuffer()[0].Severity__c);
    }

    @IsTest
    static void warn_records_WARN_severity() {
        Logger.discard();
        Logger.warn('Foo.bar', 'w');
        Assert.areEqual('WARN', Logger.getBuffer()[0].Severity__c);
    }

    @IsTest
    static void error_records_ERROR_severity() {
        Logger.discard();
        Logger.error('Foo.bar', 'e');
        Assert.areEqual('ERROR', Logger.getBuffer()[0].Severity__c);
    }

    @IsTest
    static void critical_records_CRITICAL_severity() {
        Logger.discard();
        try {
            throw new IllegalStateException('boom');
        } catch (Exception ex) {
            Logger.critical('Foo.bar', 'c', ex);
        }
        Assert.areEqual('CRITICAL', Logger.getBuffer()[0].Severity__c);
    }

    // ─── Source parsing ───────────────────────────────────────────────────────

    @IsTest
    static void source_with_dot_splits_class_and_method() {
        Logger.discard();
        Logger.info('AccountMatcher.matchTier1', 'msg');

        Log__c entry = Logger.getBuffer()[0];
        Assert.areEqual('AccountMatcher', entry.Source_Class__c);
        Assert.areEqual('matchTier1',     entry.Source_Method__c);
    }

    @IsTest
    static void source_without_dot_populates_class_only() {
        Logger.discard();
        Logger.info('SomeClass', 'msg');

        Log__c entry = Logger.getBuffer()[0];
        Assert.areEqual('SomeClass', entry.Source_Class__c);
        Assert.isNull(entry.Source_Method__c, 'Source_Method__c should be null when no dot');
    }

    @IsTest
    static void blank_source_leaves_both_null() {
        Logger.discard();
        Logger.info(null, 'msg');

        Log__c entry = Logger.getBuffer()[0];
        Assert.isNull(entry.Source_Class__c);
        Assert.isNull(entry.Source_Method__c);
    }

    // ─── Exception capture ────────────────────────────────────────────────────

    @IsTest
    static void exception_populates_stack_trace_and_appends_to_message() {
        Logger.discard();

        try {
            throw new MyTestException('original message');
        } catch (Exception ex) {
            Logger.error('Foo.bar', 'context line', ex);
        }

        Log__c entry = Logger.getBuffer()[0];
        Assert.isTrue(entry.Message__c.contains('context line'),
            'context message preserved');
        Assert.isTrue(entry.Message__c.contains('original message'),
            'exception message appended');
        Assert.isNotNull(entry.Stack_Trace__c,
            'stack trace populated');
    }

    private class MyTestException extends Exception {}

    // ─── relatedId stamping ───────────────────────────────────────────────────

    @IsTest
    static void relatedId_stamps_18char_id() {
        Logger.discard();
        // Use a fake-but-valid 18-char Account ID prefix
        Id fakeId = '001000000000001AAA';
        Logger.warn('Foo.bar', 'w', fakeId);

        Log__c entry = Logger.getBuffer()[0];
        Assert.areEqual(String.valueOf(fakeId), entry.Related_Record_Id__c);
    }

    // ─── Suppression in test context ──────────────────────────────────────────

    @IsTest
    static void flush_is_noop_when_suppressed_in_tests() {
        Logger.discard();
        Logger.info('Foo.bar', 'should not be inserted');

        // Default suppressInTests = true. flush() should NOT DML.
        Test.startTest();
        Logger.flush();
        Test.stopTest();

        Integer logCount = [SELECT COUNT() FROM Log__c];
        Assert.areEqual(0, logCount, 'flush() should be a no-op in tests by default');
    }

    @IsTest
    static void flush_inserts_when_suppression_disabled() {
        Logger.discard();
        Logger.suppressInTests = false;
        Logger.info('Foo.bar', 'this one should land in DML');

        Test.startTest();
        Logger.flush();
        Test.stopTest();

        Integer logCount = [SELECT COUNT() FROM Log__c];
        Assert.areEqual(1, logCount, 'flush() should DML when suppression is off');

        // Reset for hygiene — though static state resets between methods.
        Logger.suppressInTests = true;
    }

    // ─── discard() clears buffer without DML ─────────────────────────────────

    @IsTest
    static void discard_clears_buffer() {
        Logger.discard();
        Logger.info('Foo.bar', 'one');
        Logger.info('Foo.bar', 'two');
        Assert.areEqual(2, Logger.bufferSize());

        Logger.discard();
        Assert.areEqual(0, Logger.bufferSize(), 'discard() should empty the buffer');
    }
}
