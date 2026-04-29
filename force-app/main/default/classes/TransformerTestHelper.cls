/**
 * Shared test utilities: creates Source_System__c records and builds fixture Blobs.
 * All transformer test classes extend or reference this to avoid repetition.
 */
@IsTest
public class TransformerTestHelper {

    public static Source_System__c makeSource(String code, String transformerClass, String encoding) {
        Source_System__c ss = new Source_System__c(
            Name                = code,
            Source_Code__c      = code,
            Transformer_Class__c = transformerClass,
            File_Encoding__c    = encoding,
            Is_Active__c        = true
        );
        insert ss;
        return ss;
    }

    public static Blob utf8Blob(String content) {
        return Blob.valueOf(content);
    }

    public static Blob utf16Blob(String content) {
        // Build minimal UTF-16 BE with BOM for test purposes
        // BOM = FEFF; each ASCII char becomes 00 XX
        String hex = 'FEFF';
        for (Integer i = 0; i < content.length(); i++) {
            Integer cp = content.charAt(i);
            String byteHex = cp < 16 ? '0' + EncodingUtil.convertToHex(Blob.valueOf(String.fromCharArray(new List<Integer>{cp}))) : EncodingUtil.convertToHex(Blob.valueOf(String.fromCharArray(new List<Integer>{cp})));
            // Pad to 4 hex digits (2 bytes for UTF-16)
            hex += '00' + EncodingUtil.convertToHex(Blob.valueOf(String.fromCharArray(new List<Integer>{cp})));
        }
        return EncodingUtil.convertFromHex(hex);
    }

    public static String wideOrbitCsvHappyPath() {
        return 'advertiser_name\tagency_name\tstation\torder_type\tnet_revenue\tae_code\tbroadcast_period\n'
             + 'Acme Corp\tMediaCom\tKTVW\tLocal\t12500.00\tJD001\t2026-03\n'
             + 'Beta LLC\tOMG\tKTVW\tNational\t8000.00\tSM002\t2026-03\n';
    }

    public static String strataCsvHappyPath() {
        return 'order_guid,advertiser_name,buying_agency,station_code,revenue_type,net_revenue,ae_code,flight_month\n'
             + 'abc-123-def-456-789012345678,Acme Corp,MediaCom,KTVW,Local,12500.00,JD001,2026-03\n'
             + '00000000-0000-0000-0000-000000000000,Null Guid Corp,MediaCom,KTVW,Local,100.00,XX,2026-03\n';
    }

    public static String coxRepsCsvHappyPath() {
        return 'advertiser,agency,market_station,revenue_type,net_revenue,ae_email,period\n'
             + 'Acme Corp,MediaCom,KTVW,Local,12500.00,john.doe@coxreps.com,2026-03\n'
             + 'Beta LLC,OMG,KTVW,National,8000.00,jane.smith@coxreps.com,2026-03\n';
    }

    public static String operativeCsvHappyPath() {
        return 'advertiser_name,agency_name,station,product_type,gross_revenue,sales_rep_id,calendar_month,broadcast_month\n'
             + 'Acme Corp,MediaCom,KTVW,Digital,15000.00,REP001,2026-03,2026-04\n'
             + 'Beta LLC,OMG,KTVW,TV,9000.00,REP002,2026-03,2026-03\n';
    }

    public static String counterpointCsvHappyPath() {
        return 'advertiser,agency,station,type,amount,ae,period\n'
             + 'Acme Corp,MediaCom,KTVW,Local,12500.00,JD,2026-03\n'
             + 'Beta LLC,OMG,KTVW,National,8000.00,SM,2026-03\n';
    }
}
