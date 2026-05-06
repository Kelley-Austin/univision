public  Interface IRequestProcessor {
    RESTHandler.Request getRequest(Log thisLog);
    String toJSON();
}