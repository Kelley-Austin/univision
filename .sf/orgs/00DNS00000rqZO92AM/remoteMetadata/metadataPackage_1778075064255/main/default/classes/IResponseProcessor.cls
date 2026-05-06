public Interface IResponseProcessor {
    Log getResponse(RESTHandler.Response thisResponse, Log requestLog);
    String toJSON();
}