/**
 * The RESTHandler class is responsible for making HTTP callouts and 
 * handling responses using Named Credentials. 
 * It provides a flexible way to configure the request (method, headers, path, etc.) and 
 * process the response.
 * 
 * @author Patrick Stephens
 * @version 1.0 
 */
public without sharing class RESTHandler {

    /**
     * Default content type used if no Content-Type header is explicitly provided.
     * Common alternatives might include 'application/x-www-form-urlencoded'.
     */
    public static final String DEFAULT_CONTENT_TYPE = 'application/json';

    /**
     * An instance of the inner Request class, containing HTTP callout configuration.
     */
    public RESTHandler.Request request;

    /**
     * Primary constructor that accepts a Request object.
     *
     * @param request A Request object containing all configuration for the HTTP callout.
     */
    public RESTHandler(RESTHandler.Request request){
        this.request = request;
    }

    /**
     * Primary constructor that accepts a Log object and uses that to create a request
     *
     * @param request A Request object containing all configuration for the HTTP callout.
     */
    public RESTHandler(Log lg){
        
        String handler = null;
        for(LogXEventHandlers__mdt ph : LogX.RequestProcessHandlers){
            String handlerMatch = ph.EventName__c+ph.Type__c;
            if((lg.logEventName+'all'==handlerMatch || 'all'+lg.Type==handlerMatch || (lg.logEventName+lg.Type==handlerMatch))){
                //this is a match
                handler = ph.Handler__c;
                break;
            } 
        }
        if(handler==null && !test.isrunningTest()){
            //getHandler
            Type t = Type.forName(handler);
            RequestProcessor rP = (RequestProcessor)t.newInstance();
            //Set Request
            this.request = rP.getRequest(lg);
        } else {
            //no RequestHandler found
            //try deserializing the log content, otherwise throw an error
            try{
                this.request = (RESTHandler.Request)JSON.deserialize(lg.Content,RESTHandler.Request.class);
            } catch (exception exc){
                LogX.logException(exc, 'No Request Handler found and could not deserialize log content into Request object.',lg.CorrelationId,true);
            }
        }
    }

    /**
     * Overloaded constructor that creates a new Request object using 
     * basic parameters often needed for a REST callout.
     *
     * @param namedCredential The name of the Named Credential for the callout.
     * @param callMethod      The HTTP method (e.g., GET, POST, PUT).
     * @param path            The endpoint path relative to the Named Credential.
     * @param body            The body of the request (for POST/PUT).
     */
    public RESTHandler(String namedCredential, String callMethod, String path, String body) {
        this.request = new RESTHandler.Request();
        this.request.credential = namedCredential;
        this.request.body = body;
        this.request.path = path;
        this.request.method = callMethod;
    }
    public RESTHandler(String namedCredential, String callMethod, String path, String body, Integer timeout) {
        this.request = new RESTHandler.Request();
        this.request.credential = namedCredential;
        this.request.body = body;
        this.request.path = path;
        this.request.method = callMethod;
        this.request.timeout = timeout;
    }
    /**
     * Wraps the call to doCallout() and returns a Response object.
     * This is useful for simplifying the pattern of direct callout usage.
     *
     * @return A Response object containing the body, status code, and headers.
     */
    public RESTHandler.Response wrapCallout(){
        return new RESTHandler.Response(doCallout());
    }

    /**
     * Performs the actual HTTP callout using the current request configuration.
     * Handles timeouts, headers, content-type, disabled callout scenarios, and optional test responses.
     *
     * @return The raw HttpResponse from the callout, or a simulated test response if configured.
     */
    public HttpResponse doCallout(){

        // Log the request details for debugging.
        LogX.debug('RESTHandler Callout.', JSON.serializePretty(this.request));
 
        Http h = new Http();
        HttpRequest httpReq = new HttpRequest();

        // Determine callout timeout from either the request or LogX param.
        if(request.timeout == -1){
            request.timeout = LogX.getParamInt('CalloutTimeout');
        }
        if(request.timeout == 0){
            request.timeout = 4999; // Fallback timeout if no param was found.
        }
        if(request.timeout <= 5){
            // If the timeout is a small number of seconds, multiply by 1000 to convert to ms.
            request.timeout = request.timeout * 1000;
        }
        httpReq.setTimeout(request.timeout);

        // Set the method (GET, POST, etc.).
        httpReq.setMethod(request.method);
        // Determine the content type from the request or a default/LogX param.
        if(String.isBlank(request.contentType)){
            request.contentType = LogX.getParam('ContentType');
        }
        if(request.headers == null){
            // If no custom headers are specified, set the content-type.
            if(String.isBlank(request.contentType)){
                request.contentType = DEFAULT_CONTENT_TYPE;
            } 
            httpReq.setHeader('content-type', request.contentType);
        } else {
            // Otherwise, set each header in the request.headers list.
            for(HTTPHeader header : request.headers){
                httpReq.setHeader(header.name, header.value); 
            }
        }
        
        // Construct the endpoint using the Named Credential and path.
        httpReq.setEndpoint('callout:' + request.credential + '/' + request.path);
        if(String.isNotBlank(request.body))
            httpReq.setBody(request.body);
        LogX.debug('Method: ' + request.method + ' : ' + httpreq.getEndpoint(), request);
        // Decide whether to actually send the HTTP request or not based on config/testing.
        if(request.testResponseBody == null && LogX.getParam('DisableCallouts') != 'true'){
            // Normal production callout.
            return h.send(httpReq);

        } else if (
            (request.testResponseBody == null && LogX.getParam('DisableCallouts') == 'true') 
            || request.testResponseBody == 'ForceDisabled'
        ) {
            // If callouts are disabled, return a simulated response with status code 999.
            HTTPResponse disabledResponse = new HTTPResponse();
            disabledResponse.setStatusCode(999);
            disabledResponse.setStatus('No Callout Made');
            disabledResponse.setBody('Callouts Disabled');
            LogX.debug('RESTHandler Callout. Callouts are Disabled and we are not in Test.', JSON.serializePretty(this));
            return disabledResponse;
        } else {
            // If testResponseBody is set, return a mock response (useful for testing).
            HttpResponse tr = new HttpResponse();
            tr.setBody(request.testResponseBody);
            tr.setStatusCode(request.testResponseStatusCode);
            tr.setStatus(request.testResponseStatus);
            return tr;
        }
    }    

    /**
     * Inner class representing the necessary information to perform an HTTP callout,
     * including the path, body, method, timeout, etc. Also supports optional test response configs.
     */
    public class Request{
        public String contentType;
        
        // Method defaults to GET if unset; always uppercase for consistency.
        public String method {
            get{
                if(method == null){
                    return 'GET';
                } else {
                    return method.toUpperCase();
                }
            } set;
        }
        
        public List<HTTPHeader> headers;      // Optional custom headers
        public String credential;            // Named Credential name
        public Integer timeout = -1;         // -1 => not set, 0 => fallback, or explicit value

        // Path defaults to empty string if unset.
        public String path { 
            get{
                if(path == null){
                    path = '';
                }
                return path;
            }
            set;
        } 

        // Body defaults to empty string if unset.
        public String body {
            get{
                if(body == null){
                    body = '';
                }
                return body;
            }
            set;
        }

        // Fields for test response simulation.
        public String testResponseBody;
        
        // Defaults to HTTP 200 if not set.
        public Integer testResponseStatusCode {
            get{
                if(testResponseBody!=null && testResponseStatusCode==null){
                    testResponseStatusCode = 200;
                }
                return testResponseStatusCode;
            }
            set;
        }

        // Defaults to 'OK' if not set.
        public String testResponseStatus {
            get{
                if(testResponseBody!=null && testResponseStatus==null){
                    testResponseStatus = 'OK';
                } 
                return testResponseStatus;
            }
            set;
        }
    }

    /**
     * Represents a single HTTP header as a name-value pair.
     */
    public class HTTPHeader {
        public String name;
        public String value;
    }

    /**
     * The Response class encapsulates the relevant parts of an HTTPResponse, 
     * such as body, status, statusCode, and headers.
     */
    public class Response{

        /**
         * Constructor that takes an HttpResponse and extracts the important fields,
         * populating the current Response object.
         *
         * @param httpResponse The raw HttpResponse from an Http callout.
         */
        public Response(HttpResponse httpResponse){
            this.body = httpResponse.getBody();
            this.status = httpResponse.getStatus();
            this.statusCode = httpResponse.getStatusCode();
            headers = new List<HTTPHeader>();

            // Populate the headers list by iterating over HttpResponse header keys.
            for(String s : httpResponse.getHeaderKeys()){
                RESTHandler.HTTPHeader header = new RESTHandler.HTTPHeader();
                header.name = s;
                header.value = httpResponse.getHeader(s);
                headers.add(header);
            }
        }

        public String body { get; set; }            // HTTP response body
        public Integer statusCode { get; set; }     // HTTP status code (e.g., 200, 404)
        public String status { get; set; }          // HTTP status text (e.g., 'OK')
        public List<HTTPHeader> headers { get; set; } // Collection of headers
    }
}