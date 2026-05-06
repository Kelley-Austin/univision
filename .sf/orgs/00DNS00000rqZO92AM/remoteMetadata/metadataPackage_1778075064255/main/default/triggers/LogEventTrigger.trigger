trigger LogEventTrigger on LogEvent__e (after insert) {
    TriggerDispatcher.run(new LogEventTriggerHandler(), 'LogEventTrigger');
}