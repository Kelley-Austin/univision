trigger ImLogEventTrigger on ImLogEvent__e (after insert) {
    TriggerDispatcher.run(new LogEventTriggerHandler(), 'IMLogEventTrigger');
}