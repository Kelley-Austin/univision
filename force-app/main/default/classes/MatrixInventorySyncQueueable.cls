/**
 * Queueable job that fetches inventory changes from Matrix and updates
 * Vehicle__c avail fields. Enqueued by MatrixInventoryScheduler on each 15-minute interval.
 *
 * Conflict rule: Matrix is the system of record for inventory.
 * Vehicle__c.Matrix_Avail_Units__c and Matrix_Avail_Last_Updated__c are only
 * overwritten when the Matrix timestamp is strictly newer than what is already stored.
 */
public class MatrixInventorySyncQueueable implements Queueable, Database.AllowsCallouts {

    private final Datetime sinceTimestamp;

    public MatrixInventorySyncQueueable(Datetime since) {
        this.sinceTimestamp = since;
    }

    public void execute(QueueableContext ctx) {
        List<MatrixAPIService.InventoryRecord> changes;
        try {
            changes = MatrixAPIService.getInventoryChanges(sinceTimestamp);
        } catch (MatrixAPIService.MatrixException ex) {
            // Log and exit — the next scheduled run will retry with its own window.
            System.debug(LoggingLevel.ERROR, 'MatrixInventorySync failed: ' + ex.getMessage());
            return;
        }

        if (changes.isEmpty()) {
            return;
        }

        // Collect all vehicle external IDs from the Matrix response
        Set<String> externalIds = new Set<String>();
        for (MatrixAPIService.InventoryRecord ir : changes) {
            if (String.isNotBlank(ir.vehicle_external_id)) {
                externalIds.add(ir.vehicle_external_id);
            }
        }

        Map<String, Vehicle__c> vehiclesByExternalId = new Map<String, Vehicle__c>();
        for (Vehicle__c v : [
            SELECT Id, External_ID__c, Matrix_Avail_Units__c, Matrix_Avail_Last_Updated__c
            FROM Vehicle__c
            WHERE External_ID__c IN :externalIds
        ]) {
            vehiclesByExternalId.put(v.External_ID__c, v);
        }

        List<Vehicle__c> toUpdate = new List<Vehicle__c>();
        for (MatrixAPIService.InventoryRecord ir : changes) {
            Vehicle__c vehicle = vehiclesByExternalId.get(ir.vehicle_external_id);
            if (vehicle == null) {
                // Matrix sent data for a vehicle that doesn't exist in SF — skip.
                System.debug(LoggingLevel.WARN,
                    'MatrixInventorySync: no Vehicle__c with External_ID__c=' + ir.vehicle_external_id);
                continue;
            }

            Datetime matrixTs = parseIso8601(ir.last_updated);
            // Only apply if Matrix has newer data than what we already have
            if (vehicle.Matrix_Avail_Last_Updated__c == null
                    || matrixTs > vehicle.Matrix_Avail_Last_Updated__c) {
                vehicle.Matrix_Avail_Units__c = ir.available_units;
                vehicle.Matrix_Avail_Last_Updated__c = matrixTs;
                toUpdate.add(vehicle);
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    // Salesforce JSON deserializer handles ISO-8601 DateTime strings natively.
    private static Datetime parseIso8601(String iso) {
        if (String.isBlank(iso)) {
            return Datetime.now();
        }
        return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
    }
}
