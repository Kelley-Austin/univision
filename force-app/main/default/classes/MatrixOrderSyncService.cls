/**
 * Business logic for the outbound Salesforce → Matrix order sync.
 * Called from MatrixOrderSyncTrigger (Platform Event subscriber).
 *
 * Salesforce is the system of record for all order data.
 * Conflict rule: SF always wins on order fields; Matrix always wins on avail/inventory.
 *
 * NOTE: The Budget_Line__c child relationship name from Advertising_Opportunity__c is
 * assumed to be "Budget_Lines" (matching the object's pluralLabel). If your org uses a
 * different name, update the inner SOQL in queryBudgetLines() accordingly.
 */
public class MatrixOrderSyncService {

    // ─── Public entry point ───────────────────────────────────────────────────

    /**
     * Syncs a single Advertising Opportunity to Matrix.
     * @param opportunityId  The SF record ID.
     * @param operation      CREATE, UPDATE, or CANCEL.
     */
    public static void syncOpportunity(Id opportunityId, String operation) {
        Advertising_Opportunity__c opp = queryOpportunity(opportunityId);
        List<Budget_Line__c> budgetLines = queryBudgetLines(opportunityId);

        MatrixOrderApiService.OrderResponse resp;
        String newMatrixId = opp.Matrix_Order_ID__c;
        String syncStatus;
        String syncError;

        try {
            if (operation == 'CANCEL') {
                if (String.isBlank(opp.Matrix_Order_ID__c)) {
                    // Order was never sent to Matrix — nothing to cancel.
                    return;
                }
                resp = MatrixOrderApiService.cancelOrder(opp.Matrix_Order_ID__c);
            } else if (String.isNotBlank(opp.Matrix_Order_ID__c)) {
                MatrixOrderApiService.OrderPayload payload = buildPayload(opp, budgetLines);
                resp = MatrixOrderApiService.updateOrder(opp.Matrix_Order_ID__c, payload);
            } else {
                MatrixOrderApiService.OrderPayload payload = buildPayload(opp, budgetLines);
                resp = MatrixOrderApiService.createOrder(payload);
            }
            newMatrixId = resp.matrix_order_id;
            syncStatus = 'Synced';
        } catch (MatrixOrderApiService.MatrixException ex) {
            syncStatus = 'Failed';
            syncError = ex.getMessage().abbreviate(1000);
        }

        writeSyncResult(opportunityId, newMatrixId, syncStatus, syncError);
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static Advertising_Opportunity__c queryOpportunity(Id oppId) {
        return [
            SELECT Id, Name, Status__c, Total_Budget__c,
                   Start_Date__c, End_Date__c,
                   Matrix_Order_ID__c, Matrix_Last_Synced__c,
                   Account__c, Account__r.Matrix_Account_ID__c
            FROM Advertising_Opportunity__c
            WHERE Id = :oppId
            LIMIT 1
        ];
    }

    private static List<Budget_Line__c> queryBudgetLines(Id oppId) {
        return [
            SELECT Id, Planned_Amount__c, Calendar_Date__c,
                   Vehicle__r.Vehicle_Code__c, Vehicle__r.External_ID__c,
                   Channel__r.Channel_Code__c
            FROM Budget_Line__c
            WHERE Advertising_Opportunity__c = :oppId
            AND Status__c != 'Cancelled'
        ];
    }

    private static MatrixOrderApiService.OrderPayload buildPayload(
        Advertising_Opportunity__c opp,
        List<Budget_Line__c> lines
    ) {
        MatrixOrderApiService.OrderPayload p = new MatrixOrderApiService.OrderPayload();
        p.salesforce_id = opp.Id;
        p.matrix_account_id = opp.Account__r?.Matrix_Account_ID__c;
        p.order_name = opp.Name;
        p.status = opp.Status__c;
        p.total_budget = opp.Total_Budget__c;
        p.start_date = opp.Start_Date__c != null ? String.valueOf(opp.Start_Date__c) : null;
        p.end_date = opp.End_Date__c != null ? String.valueOf(opp.End_Date__c) : null;

        for (Budget_Line__c bl : lines) {
            MatrixOrderApiService.LineItem li = new MatrixOrderApiService.LineItem();
            li.vehicle_code = bl.Vehicle__r?.Vehicle_Code__c;
            li.channel_code = bl.Channel__r?.Channel_Code__c;
            li.planned_amount = bl.Planned_Amount__c;
            li.calendar_date = bl.Calendar_Date__c != null
                ? String.valueOf(bl.Calendar_Date__c) : null;
            p.line_items.add(li);
        }
        return p;
    }

    private static void writeSyncResult(
        Id oppId, String matrixId, String syncStatus, String syncError
    ) {
        Advertising_Opportunity__c upd = new Advertising_Opportunity__c(Id = oppId);
        upd.Matrix_Order_ID__c = matrixId;
        upd.Matrix_Sync_Status__c = syncStatus;
        upd.Matrix_Sync_Error__c = syncError;
        if (syncStatus == 'Synced') {
            upd.Matrix_Last_Synced__c = Datetime.now();
        }
        Database.update(upd, false);
    }
}
