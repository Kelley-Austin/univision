public with sharing class CancellationPolicyService {

    public class Request {
        @InvocableVariable(required=true label='Contract Id')
        public Id contractId;

        @InvocableVariable(required=true label='Request Type')
        public String requestType;

        @InvocableVariable(required=true label='Reason')
        public String reason;

        @InvocableVariable(label='Requested Credit Amount')
        public Decimal requestedCreditAmount;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Notice Period Met')
        public Boolean noticePeriodMet;

        @InvocableVariable(label='Cancellation Fee Amount')
        public Decimal cancellationFeeAmount;

        @InvocableVariable(label='Effective Fee Percent')
        public Decimal effectiveFeePercent;

        @InvocableVariable(label='Days Until Contract Start')
        public Integer daysUntilStart;

        @InvocableVariable(label='Required Notice Days')
        public Integer requiredNoticeDays;
    }

    @InvocableMethod(
        label='Process Make Good Or Cancellation'
        description='Validates the cancellation notice period, computes the fee from Cancellation_Policy__c, updates Make_Good_Credits__c or sets Contract_Status__c to Cancelled, and emails the Contract_Approvers queue.'
        category='Advertising Contract'
    )
    public static List<Result> process(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(processOne(req));
        }
        return results;
    }

    private static Result processOne(Request req) {
        Result r = new Result();
        r.success = false;

        Advertising_Contract__c contract;
        try {
            contract = [
                SELECT Id, Name, Contract_Status__c,
                       Cancellation_Policy__c, Cancellation_Notice_Days__c,
                       Cancellation_Fee_Percent__c, Make_Good_Credits__c,
                       Total_Contract_Value__c, Start_Date__c
                FROM Advertising_Contract__c
                WHERE Id = :req.contractId
                LIMIT 1
            ];
        } catch (QueryException e) {
            r.errorMessage = 'Contract not found.';
            return r;
        }

        if (req.requestType == 'Make Good') {
            return processMakeGood(contract, req, r);
        }
        return processCancellation(contract, req, r);
    }

    private static Result processMakeGood(Advertising_Contract__c contract, Request req, Result r) {
        Decimal credit = req.requestedCreditAmount != null ? req.requestedCreditAmount : 0;
        contract.Make_Good_Credits__c = (contract.Make_Good_Credits__c != null ? contract.Make_Good_Credits__c : 0) + credit;
        contract.Cancellation_Reason__c = req.reason;
        update contract;

        sendNotification(contract, 'Make Good', req.reason, null);

        r.success = true;
        r.noticePeriodMet = true;
        r.cancellationFeeAmount = 0;
        return r;
    }

    private static Result processCancellation(Advertising_Contract__c contract, Request req, Result r) {
        String policy = contract.Cancellation_Policy__c;

        if (policy == 'Non-Cancellable') {
            r.errorMessage = 'This contract is Non-Cancellable. Please contact Sales Operations for special authorization.';
            return r;
        }

        Integer requiredNoticeDays;
        Decimal feePercent;

        if (policy == 'Standard 30-Day') {
            requiredNoticeDays = 30;
            feePercent = 30;
        } else if (policy == 'Standard 60-Day') {
            requiredNoticeDays = 60;
            feePercent = 60;
        } else {
            // Custom: read from the fields already on the contract
            requiredNoticeDays = contract.Cancellation_Notice_Days__c != null
                ? contract.Cancellation_Notice_Days__c.intValue() : 0;
            feePercent = contract.Cancellation_Fee_Percent__c != null
                ? contract.Cancellation_Fee_Percent__c : 0;
        }

        r.requiredNoticeDays = requiredNoticeDays;
        r.effectiveFeePercent = feePercent;

        // Notice period = days remaining until contract start must be >= required notice days
        Integer daysUntilStart = contract.Start_Date__c != null
            ? Date.today().daysBetween(contract.Start_Date__c) : 0;
        r.daysUntilStart = daysUntilStart;
        r.noticePeriodMet = daysUntilStart >= requiredNoticeDays;

        Decimal contractValue = contract.Total_Contract_Value__c != null ? contract.Total_Contract_Value__c : 0;
        Decimal feeAmount = r.noticePeriodMet ? 0 : (contractValue * feePercent / 100).setScale(2);
        r.cancellationFeeAmount = feeAmount;

        contract.Contract_Status__c = 'Cancelled';
        contract.Cancellation_Reason__c = req.reason;
        contract.Cancellation_Request_Date__c = Date.today();
        contract.Cancellation_Fee_Percent__c = feePercent;
        contract.Cancellation_Fee_Amount__c = feeAmount;
        update contract;

        sendNotification(contract, 'Cancellation', req.reason, feeAmount);

        r.success = true;
        return r;
    }

    @TestVisible
    private static void sendNotification(Advertising_Contract__c contract, String requestType, String reason, Decimal feeAmount) {
        List<Group> queues = [
            SELECT Id, Email
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = 'Contract_Approvers'
            LIMIT 1
        ];

        if (queues.isEmpty() || String.isBlank(queues[0].Email)) {
            return;
        }

        String subject = requestType + ' Request — ' + contract.Name;
        String body = requestType + ' request submitted for contract: ' + contract.Name + '\n\n'
            + 'Reason: ' + reason + '\n';

        if (feeAmount != null && feeAmount > 0) {
            body += 'Cancellation Fee Applied: $' + feeAmount.format() + '\n';
        }
        body += '\nPlease review in Salesforce.';

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ queues[0].Email });
        email.setSubject(subject);
        email.setPlainTextBody(body);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
}
