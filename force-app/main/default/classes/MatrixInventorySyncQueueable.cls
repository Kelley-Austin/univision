public class MatrixInventorySyncQueueable implements Queueable, Database.AllowsCallouts {

    private final Boolean isManual;

    public MatrixInventorySyncQueueable(Boolean isManual) {
        this.isManual = isManual;
    }

    public void execute(QueueableContext ctx) {
        Integer processed = 0;
        Integer failed = 0;
        String errorDetail = null;
        String status = 'Success';

        try {
            List<MatrixApiService.InventoryItem> items = MatrixApiService.fetchInventory();

            Map<String, String> adSpaceByVehicleName = new Map<String, String>();
            for (MatrixApiService.InventoryItem item : items) {
                if (String.isNotBlank(item.vehicleName) && String.isNotBlank(item.adSpaceId)) {
                    adSpaceByVehicleName.put(item.vehicleName.toLowerCase().trim(), item.adSpaceId);
                }
            }

            if (adSpaceByVehicleName.isEmpty()) {
                writeLog('Success', 0, 0, 'Matrix API returned 0 active inventory items.');
                return;
            }

            List<Vehicle__c> vehicles = [
                SELECT Id, Name, Media_Cloud_Ad_Space_ID__c, Last_Matrix_Sync__c, Matrix_Sync_Status__c
                FROM Vehicle__c
                LIMIT 10000
            ];

            List<Vehicle__c> toUpdate = new List<Vehicle__c>();
            Datetime now = Datetime.now();
            for (Vehicle__c v : vehicles) {
                String key = v.Name.toLowerCase().trim();
                if (adSpaceByVehicleName.containsKey(key)) {
                    String newId = adSpaceByVehicleName.get(key);
                    if (v.Media_Cloud_Ad_Space_ID__c != newId) {
                        v.Media_Cloud_Ad_Space_ID__c = newId;
                        v.Last_Matrix_Sync__c = now;
                        v.Matrix_Sync_Status__c = 'Synced';
                        toUpdate.add(v);
                    }
                }
            }

            if (!toUpdate.isEmpty()) {
                Database.SaveResult[] results = Database.update(toUpdate, false);
                for (Database.SaveResult sr : results) {
                    if (sr.isSuccess()) {
                        processed++;
                    } else {
                        failed++;
                        if (errorDetail == null) {
                            errorDetail = sr.getErrors()[0].getMessage();
                        }
                    }
                }
                if (failed > 0) {
                    status = 'Partial';
                }
            }

        } catch (Exception e) {
            status = 'Error';
            errorDetail = e.getMessage();
        }

        writeLog(status, processed, failed, errorDetail);
    }

    private void writeLog(String status, Integer processed, Integer failed, String detail) {
        Matrix_Sync_Log__c log = new Matrix_Sync_Log__c(
            Status__c = status,
            Records_Processed__c = processed,
            Records_Failed__c = failed,
            Error_Detail__c = detail,
            Sync_Type__c = isManual ? 'Manual' : 'Scheduled'
        );
        insert log;
    }
}
