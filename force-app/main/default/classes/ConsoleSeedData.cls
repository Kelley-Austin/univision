/**
 * Demo seed data for the Sales Operations Console:
 *   - 7 Source_System__c records (one per transformer key)
 *   - 14 Load_Batch__c records spanning last 30 days
 *   - 8 Inbound_Staging__c records (5 Unmatched for KPI counter)
 *   - 1 Pacing_Snapshot__c for current month
 *
 * Invoked from anonymous Apex: ConsoleSeedData.run();
 * Deployed class used to work around anonymous Apex schema gap.
 */
public without sharing class ConsoleSeedData {

    // ------------------------------------------------------------------
    // Source file-name patterns per system (realistic demo names)
    // ------------------------------------------------------------------
    private static final Map<String, List<String>> FILE_NAMES = new Map<String, List<String>>{
        'WIDEORBIT_TV'          => new List<String>{ 'KUVS_WO_export_20260501.xml', 'EUVF_WO_export_20260508.xml', 'KUVS_WO_export_20260510.xml' },
        'WIDEORBIT_RADIO'       => new List<String>{ 'KBNT_WO_radio_20260501.csv', 'KBNT_WO_radio_20260508.csv' },
        'STRATA'                => new List<String>{ 'strata_orders_20260501.csv', 'strata_orders_20260508.csv', 'strata_orders_20260510.csv' },
        'COXREPS'               => new List<String>{ 'coxreps_billing_20260501.xlsx', 'coxreps_billing_20260508.xlsx' },
        'OPERATIVE'             => new List<String>{ 'operative_digital_20260501.json' },
        'COUNTERPOINT_CALENDAR' => new List<String>{ 'cp_calendar_20260501.csv', 'cp_calendar_20260508.csv' },
        'COUNTERPOINT_BROADCAST'=> new List<String>{ 'cp_broadcast_20260501.csv' }
    };

    private static final Map<String, Integer[]> ROW_COUNTS = new Map<String, Integer[]>{
        'WIDEORBIT_TV'          => new Integer[]{ 312, 289, 301 },
        'WIDEORBIT_RADIO'       => new Integer[]{ 148, 155 },
        'STRATA'                => new Integer[]{ 207, 198, 215 },
        'COXREPS'               => new Integer[]{ 94, 88 },
        'OPERATIVE'             => new Integer[]{ 431 },
        'COUNTERPOINT_CALENDAR' => new Integer[]{ 173, 166 },
        'COUNTERPOINT_BROADCAST'=> new Integer[]{ 142 }
    };

    private static final Map<String, Integer[]> ERR_COUNTS = new Map<String, Integer[]>{
        'WIDEORBIT_TV'          => new Integer[]{ 2, 0, 1 },
        'WIDEORBIT_RADIO'       => new Integer[]{ 0, 0 },
        'STRATA'                => new Integer[]{ 3, 12, 1 },
        'COXREPS'               => new Integer[]{ 0, 0 },
        'OPERATIVE'             => new Integer[]{ 0 },
        'COUNTERPOINT_CALENDAR' => new Integer[]{ 1, 0 },
        'COUNTERPOINT_BROADCAST'=> new Integer[]{ 0 }
    };

    private static final Map<String, String[]> STATUSES = new Map<String, String[]>{
        'WIDEORBIT_TV'          => new String[]{ 'Complete', 'Complete', 'Partial' },
        'WIDEORBIT_RADIO'       => new String[]{ 'Complete', 'Complete' },
        'STRATA'                => new String[]{ 'Complete', 'Failed', 'Complete' },
        'COXREPS'               => new String[]{ 'Complete', 'Complete' },
        'OPERATIVE'             => new String[]{ 'Complete' },
        'COUNTERPOINT_CALENDAR' => new String[]{ 'Complete', 'Complete' },
        'COUNTERPOINT_BROADCAST'=> new String[]{ 'Complete' }
    };

    // ------------------------------------------------------------------
    // Entry point
    // ------------------------------------------------------------------
    public static void run() {
        Integer totalOk = 0; Integer totalFail = 0;

        // ---- 1. Upsert Source_System__c (keyed by Code__c) ---- //
        List<Source_System__c> systems = buildSystems();
        Database.UpsertResult[] sysResults = Database.upsert(systems, Source_System__c.Code__c, false);
        Map<String, Id> sysIdByCode = new Map<String, Id>();
        for (Integer i = 0; i < sysResults.size(); i++) {
            if (sysResults[i].isSuccess()) {
                sysIdByCode.put(systems[i].Code__c, sysResults[i].getId());
                System.debug('[OK] Source_System__c upserted: ' + systems[i].Code__c + ' => ' + sysResults[i].getId());
                totalOk++;
            } else {
                System.debug('[FAIL] Source_System__c ' + systems[i].Code__c + ': ' + sysResults[i].getErrors()[0].getMessage());
                totalFail++;
            }
        }

        // ---- 2. Load_Batch__c ---- //
        List<Load_Batch__c> batches = buildBatches(sysIdByCode);
        Database.SaveResult[] batchResults = Database.insert(batches, false);
        for (Integer i = 0; i < batchResults.size(); i++) {
            if (batchResults[i].isSuccess()) {
                System.debug('[OK] Load_Batch__c: ' + batches[i].File_Name__c);
                totalOk++;
            } else {
                System.debug('[FAIL] Load_Batch__c ' + batches[i].File_Name__c + ': ' + batchResults[i].getErrors()[0].getMessage());
                totalFail++;
            }
        }

        // Collect Load_Batch Ids for Inbound_Staging linkage
        Map<String, Id> batchIdByFile = new Map<String, Id>();
        for (Integer i = 0; i < batchResults.size(); i++) {
            if (batchResults[i].isSuccess()) {
                batchIdByFile.put(batches[i].File_Name__c, batchResults[i].getId());
            }
        }

        // ---- 3. Inbound_Staging__c ---- //
        List<Inbound_Staging__c> stagings = buildStagings(sysIdByCode, batchIdByFile);
        Database.UpsertResult[] stagResults = Database.upsert(stagings, Inbound_Staging__c.Staging_Key__c, false);
        for (Integer i = 0; i < stagResults.size(); i++) {
            if (stagResults[i].isSuccess()) {
                System.debug('[OK] Inbound_Staging__c: ' + stagings[i].Staging_Key__c + ' (' + stagings[i].Status__c + ')');
                totalOk++;
            } else {
                System.debug('[FAIL] Inbound_Staging__c ' + stagings[i].Staging_Key__c + ': ' + stagResults[i].getErrors()[0].getMessage());
                totalFail++;
            }
        }

        // ---- 4. Pacing_Snapshot__c ---- //
        List<Pacing_Snapshot__c> snaps = buildSnapshots();
        Database.UpsertResult[] snapResults = Database.upsert(snaps, Pacing_Snapshot__c.Composite_Key__c, false);
        for (Integer i = 0; i < snapResults.size(); i++) {
            if (snapResults[i].isSuccess()) {
                System.debug('[OK] Pacing_Snapshot__c upserted: ' + snaps[i].Composite_Key__c);
                totalOk++;
            } else {
                System.debug('[FAIL] Pacing_Snapshot__c ' + snaps[i].Composite_Key__c + ': ' + snapResults[i].getErrors()[0].getMessage());
                totalFail++;
            }
        }

        System.debug('=== ConsoleSeedData complete: ' + totalOk + ' OK / ' + totalFail + ' FAIL ===');
    }

    // ------------------------------------------------------------------
    // Builders
    // ------------------------------------------------------------------
    private static List<Source_System__c> buildSystems() {
        return new List<Source_System__c>{
            new Source_System__c(
                Name='WideOrbit TV',
                Code__c='WIDEORBIT_TV',
                Source_Code__c='WIDEORBIT_TV',
                Is_Active__c=true,
                Transformer_Class__c='WideOrbitTransformer',
                Description__c='WideOrbit traffic system — TV linear spots and preempts',
                File_Encoding__c='UTF-8'
            ),
            new Source_System__c(
                Name='WideOrbit Radio',
                Code__c='WIDEORBIT_RADIO',
                Source_Code__c='WIDEORBIT_RADIO',
                Is_Active__c=true,
                Transformer_Class__c='WideOrbitTransformer',
                Description__c='WideOrbit traffic system — Radio linear spots',
                File_Encoding__c='UTF-8'
            ),
            new Source_System__c(
                Name='Strata',
                Code__c='STRATA',
                Source_Code__c='STRATA',
                Is_Active__c=true,
                Transformer_Class__c='StrataTransformer',
                Description__c='Strata order management — Local direct buys',
                File_Encoding__c='UTF-8'
            ),
            new Source_System__c(
                Name='CoxReps',
                Code__c='COXREPS',
                Source_Code__c='COXREPS',
                Is_Active__c=true,
                Transformer_Class__c='CoxRepsTransformer',
                Description__c='CoxReps national rep billing feed',
                File_Encoding__c='UTF-8'
            ),
            new Source_System__c(
                Name='Operative',
                Code__c='OPERATIVE',
                Source_Code__c='OPERATIVE',
                Is_Active__c=true,
                Transformer_Class__c='OperativeTransformer',
                Description__c='Operative digital ad orders',
                File_Encoding__c='UTF-8'
            ),
            new Source_System__c(
                Name='Counterpoint Calendar',
                Code__c='COUNTERPOINT_CALENDAR',
                Source_Code__c='COUNTERPOINT_CALENDAR',
                Is_Active__c=true,
                Transformer_Class__c='CounterpointTransformer',
                Description__c='Counterpoint billing — calendar month basis',
                File_Encoding__c='UTF-8'
            ),
            new Source_System__c(
                Name='Counterpoint Broadcast',
                Code__c='COUNTERPOINT_BROADCAST',
                Source_Code__c='COUNTERPOINT_BROADCAST',
                Is_Active__c=true,
                Transformer_Class__c='CounterpointTransformer',
                Description__c='Counterpoint billing — broadcast week basis',
                File_Encoding__c='UTF-8'
            )
        };
    }

    private static List<Load_Batch__c> buildBatches(Map<String, Id> sysIdByCode) {
        List<Load_Batch__c> batches = new List<Load_Batch__c>();
        // Day offsets per system per file
        Map<String, Integer[]> dayOffsets = new Map<String, Integer[]>{
            'WIDEORBIT_TV'          => new Integer[]{ 10, 3, 1 },
            'WIDEORBIT_RADIO'       => new Integer[]{ 10, 3 },
            'STRATA'                => new Integer[]{ 10, 6, 1 },
            'COXREPS'               => new Integer[]{ 10, 3 },
            'OPERATIVE'             => new Integer[]{ 5 },
            'COUNTERPOINT_CALENDAR' => new Integer[]{ 10, 3 },
            'COUNTERPOINT_BROADCAST'=> new Integer[]{ 8 }
        };

        for (String code : FILE_NAMES.keySet()) {
            if (!sysIdByCode.containsKey(code)) continue;
            Id ssId = sysIdByCode.get(code);
            List<String> files = FILE_NAMES.get(code);
            List<Integer> rows  = ROW_COUNTS.get(code);
            List<Integer> errs  = ERR_COUNTS.get(code);
            List<String> stats  = STATUSES.get(code);
            List<Integer> offs  = dayOffsets.get(code);
            for (Integer i = 0; i < files.size(); i++) {
                Integer daysAgo = offs[i];
                Datetime processedAt = Datetime.now().addDays(-daysAgo).addHours(-2);
                Load_Batch__c lb = new Load_Batch__c(
                    Source_System__c = ssId,
                    File_Name__c     = files[i],
                    Status__c        = stats[i],
                    Row_Count__c     = rows[i],
                    Error_Count__c   = errs[i],
                    Processed_At__c  = processedAt
                );
                batches.add(lb);
            }
        }
        return batches;
    }

    private static List<Inbound_Staging__c> buildStagings(Map<String, Id> sysIdByCode, Map<String, Id> batchIdByFile) {
        Id woTvId = sysIdByCode.get('WIDEORBIT_TV');
        Id woRadioId = sysIdByCode.get('WIDEORBIT_RADIO');
        Id strataId = sysIdByCode.get('STRATA');
        Id coxrepsId = sysIdByCode.get('COXREPS');

        Id bWoTv1 = batchIdByFile.get('KUVS_WO_export_20260501.xml');
        Id bWoTv2 = batchIdByFile.get('EUVF_WO_export_20260508.xml');
        Id bStrata = batchIdByFile.get('strata_orders_20260501.csv');
        Id bCox    = batchIdByFile.get('coxreps_billing_20260501.xlsx');

        return new List<Inbound_Staging__c>{
            // 5 Unmatched — show up on KPI banner
            new Inbound_Staging__c(
                Staging_Key__c       = 'SEED_WO_TV_UNMATCH_001',
                Source_System__c     = woTvId,
                Load_Batch__c        = bWoTv1,
                Status__c            = 'Unmatched',
                Station_Code__c      = 'KUVS',
                Raw_Advertiser_Name__c = 'JEEP RETAIL CORP',
                Raw_Advertiser_Code__c = 'JEP001',
                Revenue_Amount__c    = 5500,
                Period_Year__c       = 2026,
                Period_Month__c      = 5
            ),
            new Inbound_Staging__c(
                Staging_Key__c       = 'SEED_WO_TV_UNMATCH_002',
                Source_System__c     = woTvId,
                Load_Batch__c        = bWoTv1,
                Status__c            = 'Unmatched',
                Station_Code__c      = 'EUVF',
                Raw_Advertiser_Name__c = 'ADVTH CORP',
                Raw_Advertiser_Code__c = 'ADVTH01',
                Revenue_Amount__c    = 3200,
                Period_Year__c       = 2026,
                Period_Month__c      = 5
            ),
            new Inbound_Staging__c(
                Staging_Key__c       = 'SEED_WO_RADIO_UNMATCH_001',
                Source_System__c     = woRadioId,
                Status__c            = 'Unmatched',
                Station_Code__c      = 'KBNT',
                Raw_Advertiser_Name__c = 'JACK IN THE BOX INC',
                Raw_Advertiser_Code__c = 'JITB01',
                Revenue_Amount__c    = 1400,
                Period_Year__c       = 2026,
                Period_Month__c      = 5
            ),
            new Inbound_Staging__c(
                Staging_Key__c       = 'SEED_STRATA_UNMATCH_001',
                Source_System__c     = strataId,
                Load_Batch__c        = bStrata,
                Status__c            = 'Unmatched',
                Raw_Advertiser_Name__c = 'ADZWIZZ INC',
                Raw_Advertiser_Code__c = 'ADZW01',
                Revenue_Amount__c    = 8750,
                Period_Year__c       = 2026,
                Period_Month__c      = 5
            ),
            new Inbound_Staging__c(
                Staging_Key__c       = 'SEED_COXREPS_UNMATCH_001',
                Source_System__c     = coxrepsId,
                Load_Batch__c        = bCox,
                Status__c            = 'Unmatched',
                Raw_Advertiser_Name__c = 'HOMELAND SECURITY DEPT',
                Raw_Advertiser_Code__c = 'DHS001',
                Revenue_Amount__c    = 4950,
                Period_Year__c       = 2026,
                Period_Month__c      = 5
            ),
            // 2 Matched — normal reconciled rows
            new Inbound_Staging__c(
                Staging_Key__c       = 'SEED_WO_TV_MATCHED_001',
                Source_System__c     = woTvId,
                Load_Batch__c        = bWoTv2,
                Status__c            = 'Matched',
                Station_Code__c      = 'EUVF',
                Raw_Advertiser_Name__c = 'RAM TRUCK CORP',
                Raw_Advertiser_Code__c = 'RAM001',
                Revenue_Amount__c    = 6800,
                Period_Year__c       = 2026,
                Period_Month__c      = 5
            ),
            new Inbound_Staging__c(
                Staging_Key__c       = 'SEED_STRATA_MATCHED_001',
                Source_System__c     = strataId,
                Load_Batch__c        = bStrata,
                Status__c            = 'Matched',
                Raw_Advertiser_Name__c = '4U REALTY PLUS LLC',
                Raw_Advertiser_Code__c = '4URL01',
                Revenue_Amount__c    = 5200,
                Period_Year__c       = 2026,
                Period_Month__c      = 5
            ),
            // 1 Error
            new Inbound_Staging__c(
                Staging_Key__c       = 'SEED_STRATA_ERROR_001',
                Source_System__c     = strataId,
                Status__c            = 'Error',
                Raw_Advertiser_Name__c = 'MALFORMED RECORD',
                Revenue_Amount__c    = 0,
                Period_Year__c       = 2026,
                Period_Month__c      = 5
            )
        };
    }

    private static List<Pacing_Snapshot__c> buildSnapshots() {
        Date today = Date.today();
        Integer yr  = today.year();
        Integer mo  = today.month();
        String key  = 'SEED_TOTAL_' + yr + '_' + String.valueOf(mo).leftPad(2, '0') + '_' + today.format();

        // Numbers derived from seeded Opportunities:
        //   Closed Won: AdventHealth Q1 TV ($16,182) + Radio ($14,890) + AdsWizz ($291,751) = $322,823
        //   Weighted pipeline: (41,750 * 0.9) + (28,500 * 0.7) + (55,000 * 0.5) + (25,000 * 0.5) + ...
        return new List<Pacing_Snapshot__c>{
            new Pacing_Snapshot__c(
                Composite_Key__c  = key,
                Snapshot_Date__c  = today,
                Period_Year__c    = yr,
                Period_Month__c   = mo,
                Booked_Amount__c  = 322823,
                Forecast_Amount__c= 498640,
                Budget_Amount__c  = 620000,
                Actual_Amount__c  = 289500,
                Pending_Amount__c = 87200,
                Last_Year_Amount__c = 412000
            )
        };
    }
}
