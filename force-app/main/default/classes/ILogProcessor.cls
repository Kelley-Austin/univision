public Interface ILogProcessor {
    LogProcessor.Result processLogs();
    ILogProcessor setLogs(List<Log> logs);
}