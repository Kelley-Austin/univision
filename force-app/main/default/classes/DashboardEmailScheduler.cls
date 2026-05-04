public without sharing class DashboardEmailScheduler implements Schedulable {

    public static final String SALES_MANAGER_JOB    = 'Sales Manager Dashboard Email — Weekly';
    public static final String WEEKLY_ANALYTICS_JOB = 'Weekly Analytics Dashboard Email — Friday';

    @TestVisible static final String TYPE_SALES_MANAGER    = 'SALES_MANAGER';
    @TestVisible static final String TYPE_WEEKLY_ANALYTICS = 'WEEKLY_ANALYTICS';

    // Injected in tests to bypass PermissionSetAssignment queries.
    @TestVisible static List<String> overrideRecipients;

    private final String emailType;

    public DashboardEmailScheduler(String emailType) {
        this.emailType = emailType;
    }

    public void execute(SchedulableContext ctx) {
        if (TYPE_SALES_MANAGER.equals(emailType)) {
            sendSalesManagerDigest();
        } else {
            sendWeeklyAnalyticsDigest();
        }
    }

    // ── Scheduling ────────────────────────────────────────────────────────────

    /** Schedules (or re-schedules) the Sales Manager email for every Monday at 7 AM. */
    public static void scheduleSalesManager() {
        abortExisting(SALES_MANAGER_JOB);
        System.schedule(SALES_MANAGER_JOB, '0 0 7 ? * MON', new DashboardEmailScheduler(TYPE_SALES_MANAGER));
    }

    /** Schedules (or re-schedules) the Weekly Analytics email for every Friday at 4 PM. */
    public static void scheduleWeeklyAnalytics() {
        abortExisting(WEEKLY_ANALYTICS_JOB);
        System.schedule(WEEKLY_ANALYTICS_JOB, '0 0 16 ? * FRI', new DashboardEmailScheduler(TYPE_WEEKLY_ANALYTICS));
    }

    public static void abortExisting(String jobName) {
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
            AND State NOT IN ('DELETED', 'COMPLETE')
        ]) {
            System.abortJob(ct.Id);
        }
    }

    public static Boolean isSalesManagerScheduled() {
        return ![
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :SALES_MANAGER_JOB
            AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 1
        ].isEmpty();
    }

    public static Boolean isWeeklyAnalyticsScheduled() {
        return ![
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :WEEKLY_ANALYTICS_JOB
            AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 1
        ].isEmpty();
    }

    // ── Email Dispatch ────────────────────────────────────────────────────────

    @TestVisible
    void sendSalesManagerDigest() {
        List<String> recipients = resolveRecipients(new Set<String>{ 'Sales_Manager' });
        if (recipients.isEmpty()) return;
        dispatch(
            'Sales Manager Dashboard — ' + Date.today().format(),
            buildSalesManagerBody(),
            recipients
        );
    }

    @TestVisible
    void sendWeeklyAnalyticsDigest() {
        List<String> recipients = resolveRecipients(new Set<String>{ 'Sales_Manager', 'Sales_Rep' });
        if (recipients.isEmpty()) return;
        dispatch(
            'Weekly Analytics Dashboard — ' + Date.today().format(),
            buildWeeklyAnalyticsBody(),
            recipients
        );
    }

    private static void dispatch(String subject, String htmlBody, List<String> toAddresses) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(toAddresses);
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setSenderDisplayName('TelevisaUnivision Analytics');
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }

    // ── Body Builders ─────────────────────────────────────────────────────────

    @TestVisible
    static String buildSalesManagerBody() {
        Integer yr = Date.today().year();

        List<AggregateResult> pipelineByMarket = [
            SELECT Market__c mkt, OwnerId oid,
                   SUM(Total_Budget__c) pipeline
            FROM Advertising_Opportunity__c
            WHERE Status__c NOT IN ('Cancelled', 'Closed')
            AND Fiscal_Year__c = :yr
            GROUP BY Market__c, OwnerId
            ORDER BY Market__c
        ];

        List<AggregateResult> repYtd = [
            SELECT OwnerId oid,
                   SUM(Total_Budget__c) pipeline,
                   SUM(Total_Actual_Amount__c) actual,
                   COUNT(Id) cnt
            FROM Advertising_Opportunity__c
            WHERE Fiscal_Year__c = :yr
            GROUP BY OwnerId
            ORDER BY OwnerId
        ];

        List<AggregateResult> dealAging = [
            SELECT Status__c status, COUNT(Id) cnt
            FROM Advertising_Opportunity__c
            WHERE Status__c NOT IN ('Cancelled', 'Closed')
            AND Fiscal_Year__c = :yr
            GROUP BY Status__c
            ORDER BY Status__c
        ];

        Map<Id, String> ownerNames = resolveUserNames(collectIds(pipelineByMarket, repYtd, 'oid'));

        String h = '<html><body style="font-family:Arial,sans-serif;color:#333;">';
        h += '<h2 style="color:#003366;">Sales Manager Dashboard — ' + Date.today().format() + '</h2>';

        h += '<h3>Pipeline by Market</h3>';
        h += tableHeader(new List<String>{ 'Market', 'Rep', 'Pipeline Value' });
        for (AggregateResult ar : pipelineByMarket) {
            String mkt  = ar.get('mkt')  != null ? String.valueOf(ar.get('mkt'))  : '(No Market)';
            String rep  = ownerNames.get((Id) ar.get('oid'));
            Decimal val = ar.get('pipeline') != null ? (Decimal) ar.get('pipeline') : 0;
            h += '<tr><td>' + mkt + '</td><td>' + rep + '</td><td>$' + val.setScale(0).format() + '</td></tr>';
        }
        if (pipelineByMarket.isEmpty()) h += emptyRow(3, 'No active pipeline');
        h += '</table>';

        h += '<h3>Rep YTD Performance</h3>';
        h += tableHeader(new List<String>{ 'Rep', 'YTD Pipeline', 'YTD Actual', 'Opp Count' });
        for (AggregateResult ar : repYtd) {
            String rep      = ownerNames.get((Id) ar.get('oid'));
            Decimal pipeline = ar.get('pipeline') != null ? (Decimal) ar.get('pipeline') : 0;
            Decimal actual   = ar.get('actual')   != null ? (Decimal) ar.get('actual')   : 0;
            Integer cnt      = ar.get('cnt')       != null ? Integer.valueOf(ar.get('cnt')) : 0;
            h += '<tr><td>' + rep + '</td><td>$' + pipeline.setScale(0).format()
                + '</td><td>$' + actual.setScale(0).format() + '</td><td>' + cnt + '</td></tr>';
        }
        if (repYtd.isEmpty()) h += emptyRow(4, 'No data');
        h += '</table>';

        h += '<h3>Active Pipeline by Stage</h3>';
        h += tableHeader(new List<String>{ 'Stage', 'Count' });
        for (AggregateResult ar : dealAging) {
            String stage = ar.get('status') != null ? String.valueOf(ar.get('status')) : '(Unknown)';
            Integer cnt  = Integer.valueOf(ar.get('cnt'));
            h += '<tr><td>' + stage + '</td><td>' + cnt + '</td></tr>';
        }
        if (dealAging.isEmpty()) h += emptyRow(2, 'No active deals');
        h += '</table>';

        h += footer();
        return h;
    }

    @TestVisible
    static String buildWeeklyAnalyticsBody() {
        Integer yr = Date.today().year();

        List<AggregateResult> vehiclePacing = [
            SELECT Vehicle__c vId, SUM(Planned_Amount__c) planned, SUM(Actual_Amount__c) actual
            FROM Budget_Line__c
            WHERE Status__c != 'Cancelled'
            AND Fiscal_Year__c = :yr
            GROUP BY Vehicle__c
            ORDER BY Vehicle__c
        ];

        List<AggregateResult> channelPacing = [
            SELECT Channel__c cId, SUM(Planned_Amount__c) planned, SUM(Actual_Amount__c) actual
            FROM Budget_Line__c
            WHERE Status__c != 'Cancelled'
            AND Fiscal_Year__c = :yr
            GROUP BY Channel__c
            ORDER BY Channel__c
        ];

        List<AggregateResult> revByMarket = [
            SELECT Market__c mkt, SUM(Total_Budget__c) budget, SUM(Total_Actual_Amount__c) actual
            FROM Advertising_Opportunity__c
            WHERE Fiscal_Year__c = :yr
            GROUP BY Market__c
            ORDER BY Market__c
        ];

        List<AggregateResult> orderPacing = [
            SELECT Traffic_Status__c tStatus, COUNT(Id) cnt, SUM(Total_Contract_Value__c) val
            FROM Advertising_Contract__c
            WHERE Contract_Status__c NOT IN ('Cancelled', 'Completed')
            GROUP BY Traffic_Status__c
            ORDER BY Traffic_Status__c
        ];

        Map<Id, String> vehicleNames = resolveRecordNames(vehiclePacing, 'vId', 'Vehicle__c');
        Map<Id, String> channelNames = resolveRecordNames(channelPacing, 'cId', 'Channel__c');

        String h = '<html><body style="font-family:Arial,sans-serif;color:#333;">';
        h += '<h2 style="color:#003366;">Weekly Analytics Dashboard — ' + Date.today().format() + '</h2>';

        h += '<h3>Budget vs. Actuals Pacing by Vehicle</h3>';
        h += tableHeader(new List<String>{ 'Vehicle', 'Budget', 'Actuals', 'Variance', 'Pacing %' });
        for (AggregateResult ar : vehiclePacing) {
            h += pacingRow(vehicleNames.get((Id) ar.get('vId')), ar, '(No Vehicle)');
        }
        if (vehiclePacing.isEmpty()) h += emptyRow(5, 'No vehicle data');
        h += '</table>';

        h += '<h3>Budget vs. Actuals Pacing by Channel</h3>';
        h += tableHeader(new List<String>{ 'Channel', 'Budget', 'Actuals', 'Variance', 'Pacing %' });
        for (AggregateResult ar : channelPacing) {
            h += pacingRow(channelNames.get((Id) ar.get('cId')), ar, '(No Channel)');
        }
        if (channelPacing.isEmpty()) h += emptyRow(5, 'No channel data');
        h += '</table>';

        h += '<h3>Revenue by Market (YTD)</h3>';
        h += tableHeader(new List<String>{ 'Market', 'Budget', 'Actual' });
        for (AggregateResult ar : revByMarket) {
            String mkt    = ar.get('mkt')    != null ? String.valueOf(ar.get('mkt'))    : '(No Market)';
            Decimal budget = ar.get('budget') != null ? (Decimal) ar.get('budget')      : 0;
            Decimal actual = ar.get('actual') != null ? (Decimal) ar.get('actual')      : 0;
            h += '<tr><td>' + mkt + '</td><td>$' + budget.setScale(0).format()
                + '</td><td>$' + actual.setScale(0).format() + '</td></tr>';
        }
        if (revByMarket.isEmpty()) h += emptyRow(3, 'No data');
        h += '</table>';

        h += '<h3>Order Pacing by Traffic Status</h3>';
        h += tableHeader(new List<String>{ 'Traffic Status', 'Count', 'Total Value' });
        for (AggregateResult ar : orderPacing) {
            String status = ar.get('tStatus') != null ? String.valueOf(ar.get('tStatus')) : '(Not Set)';
            Integer cnt   = Integer.valueOf(ar.get('cnt'));
            Decimal val   = ar.get('val') != null ? (Decimal) ar.get('val') : 0;
            h += '<tr><td>' + status + '</td><td>' + cnt + '</td><td>$' + val.setScale(0).format() + '</td></tr>';
        }
        if (orderPacing.isEmpty()) h += emptyRow(3, 'No active orders');
        h += '</table>';

        h += footer();
        return h;
    }

    // ── HTML Helpers ──────────────────────────────────────────────────────────

    private static String tableHeader(List<String> cols) {
        String s = '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%;margin-bottom:16px;">';
        s += '<tr style="background:#003366;color:#fff;">';
        for (String c : cols) s += '<th>' + c + '</th>';
        return s + '</tr>';
    }

    private static String emptyRow(Integer cols, String msg) {
        return '<tr><td colspan="' + cols + '" style="text-align:center;color:#999;">' + msg + '</td></tr>';
    }

    private static String footer() {
        return '<p style="font-size:11px;color:#999;">Generated by TelevisaUnivision Analytics — '
            + System.now().format() + '</p></body></html>';
    }

    private static String pacingRow(String label, AggregateResult ar, String fallback) {
        String name  = label != null ? label : fallback;
        Decimal plan = ar.get('planned') != null ? (Decimal) ar.get('planned') : 0;
        Decimal act  = ar.get('actual')  != null ? (Decimal) ar.get('actual')  : 0;
        Decimal vari = act - plan;
        String pct   = plan != 0 ? (act / plan * 100).setScale(1).format() + '%' : 'N/A';
        String color = vari >= 0 ? 'green' : 'red';
        return '<tr><td>' + name + '</td><td>$' + plan.setScale(0).format()
            + '</td><td>$' + act.setScale(0).format()
            + '</td><td style="color:' + color + ';">$' + vari.setScale(0).format()
            + '</td><td>' + pct + '</td></tr>';
    }

    // ── Data Helpers ──────────────────────────────────────────────────────────

    private static List<String> resolveRecipients(Set<String> permSetNames) {
        if (overrideRecipients != null) return overrideRecipients;
        Set<String> emails = new Set<String>();
        for (PermissionSetAssignment psa : [
            SELECT Assignee.Email
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name IN :permSetNames
            AND Assignee.IsActive = true
            AND Assignee.Email != null
        ]) {
            emails.add(psa.Assignee.Email);
        }
        return new List<String>(emails);
    }

    private static Set<Id> collectIds(List<AggregateResult> a, List<AggregateResult> b, String key) {
        Set<Id> ids = new Set<Id>();
        for (AggregateResult ar : a) { if (ar.get(key) != null) ids.add((Id) ar.get(key)); }
        for (AggregateResult ar : b) { if (ar.get(key) != null) ids.add((Id) ar.get(key)); }
        return ids;
    }

    private static Map<Id, String> resolveUserNames(Set<Id> ids) {
        Map<Id, String> m = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :ids]) m.put(u.Id, u.Name);
        return m;
    }

    private static Map<Id, String> resolveRecordNames(List<AggregateResult> results, String key, String objectType) {
        Set<Id> ids = new Set<Id>();
        for (AggregateResult ar : results) {
            if (ar.get(key) != null) ids.add((Id) ar.get(key));
        }
        Map<Id, String> m = new Map<Id, String>();
        if (ids.isEmpty()) return m;
        String soql = 'SELECT Id, Name FROM ' + objectType + ' WHERE Id IN :ids';
        for (SObject rec : Database.query(soql)) {
            m.put(rec.Id, (String) rec.get('Name'));
        }
        return m;
    }
}
