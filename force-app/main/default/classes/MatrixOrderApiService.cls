/**
 * HTTP callout wrapper for the Matrix advertising system REST API — order operations
 * plus incremental inventory polling. Companion to MatrixInventoryApiService (full inventory sync).
 *
 * All methods assume they run in a context that allows callouts
 * (e.g., a Platform Event trigger or a Queueable implementing Database.AllowsCallouts).
 *
 * Authentication is handled by the "Matrix_API" Named Credential.
 * Configure the endpoint URL and credentials in Setup → Named Credentials before deploying.
 */
public class MatrixOrderApiService {

    private static final String NC = 'callout:Matrix_API';
    private static final Integer TIMEOUT_MS = 30000;

    public class MatrixException extends Exception {}

    /** Payload sent to Matrix when creating or updating an order. */
    public class OrderPayload {
        public String salesforce_id;
        public String matrix_account_id;
        public String order_name;
        public String status;
        public Decimal total_budget;
        public String start_date;
        public String end_date;
        public List<LineItem> line_items = new List<LineItem>();
    }

    public class LineItem {
        public String vehicle_code;
        public String channel_code;
        public Decimal planned_amount;
        public String calendar_date;
    }

    /** Response body from Matrix order endpoints. */
    public class OrderResponse {
        public String matrix_order_id;
        public String status;
        public String message;
    }

    /** Single inventory record returned by the Matrix /inventory endpoint. */
    public class InventoryRecord {
        public String vehicle_external_id;
        public Integer available_units;
        public String last_updated;
    }

    /** Wrapper around the Matrix /inventory response envelope. */
    public class InventoryResponse {
        public List<InventoryRecord> records;
    }

    public static OrderResponse createOrder(OrderPayload payload) {
        HttpRequest req = buildRequest('POST', NC + '/orders');
        req.setBody(JSON.serialize(payload));
        return parseOrderResponse(execute(req));
    }

    public static OrderResponse updateOrder(String matrixOrderId, OrderPayload payload) {
        String path = NC + '/orders/' + EncodingUtil.urlEncode(matrixOrderId, 'UTF-8');
        HttpRequest req = buildRequest('PUT', path);
        req.setBody(JSON.serialize(payload));
        return parseOrderResponse(execute(req));
    }

    public static OrderResponse cancelOrder(String matrixOrderId) {
        String path = NC + '/orders/' + EncodingUtil.urlEncode(matrixOrderId, 'UTF-8') + '/cancel';
        HttpRequest req = buildRequest('POST', path);
        req.setBody('{}');
        return parseOrderResponse(execute(req));
    }

    /**
     * Fetches inventory changes from Matrix since the given timestamp.
     * Returns an empty list when Matrix reports no changes.
     */
    public static List<InventoryRecord> getInventoryChanges(Datetime since) {
        String sinceStr = since.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        String path = NC + '/inventory?since=' + EncodingUtil.urlEncode(sinceStr, 'UTF-8');
        HttpRequest req = buildRequest('GET', path);
        req.setTimeout(60000);
        HttpResponse res = execute(req);
        if (res.getStatusCode() != 200) {
            throw new MatrixException(
                'Inventory fetch failed [' + res.getStatusCode() + ']: ' + res.getBody()
            );
        }
        InventoryResponse parsed =
            (InventoryResponse) JSON.deserialize(res.getBody(), InventoryResponse.class);
        return parsed.records != null ? parsed.records : new List<InventoryRecord>();
    }

    private static HttpRequest buildRequest(String method, String endpoint) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        return req;
    }

    @TestVisible
    private static HttpResponse execute(HttpRequest req) {
        return new Http().send(req);
    }

    private static OrderResponse parseOrderResponse(HttpResponse res) {
        Integer code = res.getStatusCode();
        if (code == 200 || code == 201 || code == 202) {
            return (OrderResponse) JSON.deserialize(res.getBody(), OrderResponse.class);
        }
        throw new MatrixException(
            'Matrix API error [' + code + ']: ' + res.getBody()
        );
    }
}
