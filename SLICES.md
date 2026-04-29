# TelevisaUnivision Matrix — Development Slices

Source: `TelevisaUnivision_Matrix_Requirements_User_Stories.xlsx`
Stories: 73 total (67 Phase 1 + 6 Phase 2 deferred)
Slices: 23 (22 active + 1 Phase 2 documentation slice)

Each slice is independently implementable by a subagent. Stories within a slice share a data model, a domain boundary, or a tight build dependency. Cross-slice dependencies are called out explicitly.

---

## Dependency Build Order

```
Slice 1  (Platform Foundation)
  └─► Slice 2  (MDM Account Hierarchy)
        └─► Slice 3  (MDM Category Taxonomy)
        └─► Slice 4  (MDM Workspace & Triage)
        └─► Slice 5  (MDM Reporting Hierarchies)
  └─► Slice 6  (Pipeline Core)
        └─► Slice 7  (Source Transformers)
        └─► Slice 8  (Pipeline Rules & Telemetry)
  └─► Slices 9-11 (Reconciliation — needs Slice 2, 6, 7)
        └─► Slices 12-13 (Forecast — needs Slice 9-11)
              └─► Slices 14-15 (Period Close — needs Slice 11, 12)
  └─► Slice 16 (Sales Ops Console — needs Slice 6, 8, 11)
  └─► Slices 17-20 (Reporting — needs Slices 11, 12, 14)
  └─► Slices 21-22 (Pitch Projects — needs Slices 9, 12)
```

---

## Slice 1 — Platform Foundation & Deployment

**Branch:** `agent/platform-foundation`
**Stories:** 7-001, 7-002, 7-003, 7-004, 7-005
**Estimated Hours:** ~108h
**Depends on:** Nothing — build first

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 7-001 | Permission Set Architecture | 24h |
| 7-002 | Sharing Rules and Hierarchy Access | 16h |
| 7-003 | SFDX Project and Deploy Script | 12h |
| 7-004 | Cutover Migration Plan | 24h |
| 7-005 | Test Coverage and Fixture Strategy | 32h |

### Deliverables
- Five permission sets in `force-app/main/default/permissionsets/`: `MatrixCore_AE`, `MatrixCore_SalesOps`, `MatrixCore_SalesManager`, `MatrixCore_MDMCurator`, `MatrixCore_Admin`
- Custom permissions in `customPermissions/`: `Period_Close_Admin`, `Bulk_Reconciliation`, `MDM_Curator`
- OWD settings documented; sharing rules per object per SDD §7
- `sfdx-project.json`, `.forceignore`, `.gitignore`, scratch org definition file
- Cutover runbook with stabilization checkpoints at T+1, T+3, T+7, T+14
- Test fixture strategy documented in `tests/fixtures/README.md`; fixture files for all source transformers

---

## Slice 2 — MDM: Account Hierarchy & Reference Data

**Branch:** `agent/mdm-account-hierarchy`
**Stories:** 1-001, 1-002, 1-008, 1-009
**Estimated Hours:** ~44h
**Depends on:** Slice 1

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 1-001 | Buy-Side Account Record Types | 16h |
| 1-002 | Primary AE Assignment | 8h |
| 1-008 | Matrix Legacy ID Migration | 4h |
| 1-009 | Medium Reference Data with Outlet Auto-Derivation | 16h |

### Deliverables
- Three Account record types: `HoldCo`, `Agency`, `Advertiser`; page layouts `HoldCo_Layout`, `Agency_Layout`, `Advertiser_Layout`
- Validation rule: Advertiser cannot parent another Advertiser
- `Account.Primary_AE__c` (Lookup to User); required on Advertiser via `VR_Advertiser_Requires_Primary_AE`; field history tracking enabled
- `Account.Matrix_Legacy_Id__c` (read-only except System Admin)
- `Medium__c` custom object with `Outlet__c` auto-derivation lookup; seed CSV: `data/seed/Medium.csv`

### Cross-Slice Notes
- `Primary_AE__c` consumed by `SalespersonMatcher` Tier 4 fallback (Slice 9)
- `Matrix_Legacy_Id__c` referenced in Cutover runbook (Slice 1)

---

## Slice 3 — MDM: Category Taxonomy

**Branch:** `agent/mdm-category-taxonomy`
**Stories:** 1-003, 1-004
**Estimated Hours:** ~68h
**Depends on:** Slice 2

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 1-003 | Category Hierarchy with Retire-with-Successor | 40h |
| 1-004 | Multi-Category Account Support | 28h |

### Deliverables
- `Category__c` object: `Parent_Category__c` (self-lookup), `Status` (Active/Retired picklist), `Successor_Category__c`
- LWC `categoryTaxonomyTree` (E1-C13): drag-to-reparent tree editor with inline rename
- Apex `CategoryService`: retire-with-successor logic; cycle prevention; `Retired_Requires_Successor_If_Active_Junctions` validation
- `Account_Category__c` junction object: many-to-many Account ↔ Category
- `Account_Category_Count__c` rollup summary (or flow-maintained) on Account
- Retired Categories filtered from all pickers; active Categories visible

### Cross-Slice Notes
- `Account_Category__c` junction referenced by Actual Revenue category snapshot (Slice 11a)
- Category retire-with-successor must not break historical `Category_Snapshot__c` on Actual_Revenue__c

---

## Slice 4 — MDM: Workspace & Triage

**Branch:** `agent/mdm-workspace-triage`
**Stories:** 1-005, 1-006, 1-007
**Estimated Hours:** ~62h
**Depends on:** Slices 2, 3

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 1-005 | MDM Workspace Lightning App | 24h |
| 1-006 | MDM Triage Resolution | 32h |
| 1-007 | Bulk Account Cleanup Worklist | 6h |

### Deliverables
- Lightning App `MDM_Workspace` (E1-C10)
- Lightning Page `MDM_Home` with LWC `mdmHomeKpis` (E1-C11): KPI dashboard + recent-changes feed
- Tabs: `MDM_Triage_Item__c` (standard list), Category Taxonomy (hosts `categoryTaxonomyTree`), Account Curation (filtered list view)
- `MDM_Triage_Item__c` custom object with triage status flow
- List view `Recently_Edited_Advertisers` on Account; `Account_Category_Count__c` used as visual flag

---

## Slice 5 — MDM: Reporting Hierarchies & Account Analytics

**Branch:** `agent/mdm-reporting-hierarchies`
**Stories:** 1-010, 1-011, 1-012
**Estimated Hours:** ~80h
**Depends on:** Slice 2

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 1-010 | Outlet Group, Office Group, Agency Group Reference Hierarchies | 32h |
| 1-011 | Region Mapping with Declarative Override Rules | 24h |
| 1-012 | Account Year-over-Year Spend Summary | 24h |

### Deliverables
- Three reporting hierarchy objects: `Outlet_Group__c`, `Office_Group__c`, `Agency_Group__c` (decoupled from Salesforce role hierarchy)
- Lookup fields on Account to each group; seed data CSVs
- `Region_Mapping__c` declarative rules object (replaces Excel macro for region assignment)
- LWC or Flow-based region derivation; override field on Account
- Account YoY Spend Summary component/report (LWC or CRT): last 2 years of `Actual_Revenue__c` rolled up per Account

### Cross-Slice Notes
- `Outlet_Group__c`, `Office_Group__c` referenced by Projections (Slice 12) and Reporting (Slices 17-20)
- Region Mapping rules consumed by reconciliation salesperson matching (Slice 9) and report grouping (Slices 17-20)

---

## Slice 6 — Pipeline: Core Staging & Orchestration

**Branch:** `agent/pipeline-core`
**Stories:** 2-001, 2-002, 2-003, 2-004, 4-005
**Estimated Hours:** ~102h
**Depends on:** Slice 1

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 2-001 | Source System Configuration Records | 8h |
| 2-002 | Canonical 13-Field Staging Object | 16h |
| 2-003 | Sales Ops File Upload | 12h |
| 2-004 | IngestService Orchestrator | 60h |
| 4-005 | Outlet, Revenue Type, Calendar Type Reference Data | 6h |

### Deliverables
- `Source_System__c` (E2-C02) custom object; seed CSV: `data/seed/Source_System.csv` (7 rows)
- `Inbound_Staging__c` (E2-C01): 13 canonical fields + orchestration fields (`Load_Batch__c`, `Status__c`, `Excluding_Rule__c`)
- `Load_Batch__c` custom object for file-level tracking
- `ContentDocumentLinkTrigger` (E2-C15): detects upload, validates, creates `Load_Batch`, enqueues `IngestQueueable`
- Lightning page component on `Source_System__c` record page for file upload UX
- `IngestService` (E2-C05): main orchestrator; `IngestQueueable` (E2-C05): async chain
- `TransformerRegistry` (E2-C06): maps `Source_System__c` to transformer class; `SourceSystemTransformer` interface
- `MappingRuleExecutor` (E2-C13): applies active `Mapping_Rule__c` records during staging
- `Outlet__c`, `Revenue_Type__c` custom objects; `Calendar_Type` restricted picklist; seed CSVs in `data/seed/`

### Cross-Slice Notes
- `IngestService` interface (`SourceSystemTransformer`) must be in place before Slice 7 (Transformers) starts
- `Inbound_Staging__c` schema must be locked before any transformer writes to it

---

## Slice 7 — Pipeline: Source Transformers

**Branch:** `agent/pipeline-transformers`
**Stories:** 2-005, 2-006, 2-007, 2-008, 2-009
**Estimated Hours:** ~64h
**Depends on:** Slice 6 (TransformerRegistry, SourceSystemTransformer interface, Inbound_Staging__c schema)

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 2-005 | WideOrbit Transformer (TV and Radio) | 16h |
| 2-006 | Strata Transformer | 12h |
| 2-007 | CoxReps Transformer | 8h |
| 2-008 | Operative Transformer (Two-Row Split) | 16h |
| 2-009 | Counterpoint Transformer (Calendar and Broadcast) | 12h |

### Deliverables
- `WideOrbitTransformer` (E2-C07): handles TV and Radio; Custom MDT `Revenue_Code_Mapping__mdt`; fixture: `tests/fixtures/wideorbit_tv/happy_path.tsv`
- `StrataTransformer` (E2-C08); excluded rows retain audit visibility; fixture: `tests/fixtures/strata/happy_path.csv`
- `CoxRepsTransformer` (E2-C09); documented field name typos in SDD §2.2
- `OperativeTransformer` (E2-C10): two-row emission logic (critical complexity); fixture: `tests/fixtures/operative/happy_path.csv`
- `CounterpointTransformer` (E2-C11): shared for Calendar and Broadcast variants; CP1252 decode at `IngestService` layer; Custom MDT for network-code mapping
- All transformers registered in `TransformerRegistry`

### Cross-Slice Notes
- `CounterpointTransformer` must align with canonical `Counterpoint` object naming — resolve naming conflict between `Actual_Revenue__c` vs `Actuals_Record__c` (noted in project context) before this slice starts

---

## Slice 8 — Pipeline: Mapping Rules & Telemetry

**Branch:** `agent/pipeline-rules-telemetry`
**Stories:** 2-010, 2-011
**Estimated Hours:** ~56h
**Depends on:** Slice 6

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 2-010 | Mapping Rule Editor | 32h |
| 2-011 | Load Batch Dashboard | 24h |

### Deliverables
- `Mapping_Rule__c` custom object; validation rule `Active_Requires_Notes`
- LWC `mappingRuleEditor` (E2-C12) with Apex `MappingRuleService` (methods: `dryRun`, `saveRule`, `activateRule`)
- LWC `loadBatchDashboard` (E2-C16): file upload history, status, error counts per source
- Apex `LoadBatchDashboardController` with `@AuraEnabled(cacheable=true)`; `Source_System.Last_Uploaded_At` drives staleness indicator

---

## Slice 9 — Reconciliation: Matching Engines

**Branch:** `agent/reconciliation-matching`
**Stories:** 3-001, 3-002
**Estimated Hours:** ~80h
**Depends on:** Slices 2, 6 (Account data, staging records)

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 3-001 | Three-Tier Account Match | 32h |
| 3-002 | Five-Tier Salesperson Match with Self-Healing Aliases | 48h |

### Deliverables
- `AccountMatcher` (E3-C04): Tier 1 (exact ID), Tier 2 (normalized name), Tier 3 (fuzzy/Levenshtein deferred); `Normalized_Name__c` formula field on Account
- `SalespersonMatcher` (E3-C05): five tiers with alias persistence; Tier 4 falls back to `Account.Primary_AE__c`
- `User_Name_Alias__c` (E3-C03) custom object: alias → User mapping, self-healing on successful match
- Decision log: each match records tier used + confidence score on `Inbound_Staging__c`

### Cross-Slice Notes
- Both matchers are dependencies for `ReconciliationEngine` (Slice 10)
- `User_Name_Alias__c` populated during Reconciliation resolution (Slice 10); created here as schema only

---

## Slice 10 — Reconciliation: Engine & Worklists

**Branch:** `agent/reconciliation-engine-worklists`
**Stories:** 3-003, 3-004, 3-005
**Estimated Hours:** ~104h
**Depends on:** Slice 9 (AccountMatcher, SalespersonMatcher)

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 3-003 | Reconciliation Engine | 56h |
| 3-004 | AE Reconciliation Worklist | 32h |
| 3-005 | Sales Ops Bulk Reconciliation | 16h |

### Deliverables
- `ReconciliationEngine` (E3-C06): idempotent orchestrator; chains `AccountMatcher` → `SalespersonMatcher` → writes `Actual_Revenue__c`
- `ReconciliationQueueable` (E3-C06): async chaining for large batches; safe to invoke from trigger after-update
- LWC `reconciliationWorklist` (E3-C07): single component with `scope` prop (`AE` or `SalesOps`)
  - AE scope (3-004): per-AE unmatched staging records; resolution updates `User_Name_Alias__c`
  - Sales Ops scope (3-005): bulk-accept with threshold UI
- Apex `ReconciliationWorklistController`

### Cross-Slice Notes
- `ReconciliationEngine` must produce `Actual_Revenue__c` records consumed by Slice 11a
- Reconciliation trigger integration point: `MDMTriageTrigger` after-update (Slice 4)

---

## Slice 11a — Reconciliation: Actual Revenue & Projection Rollups

**Branch:** `agent/reconciliation-actuals-rollups`
**Stories:** 3-006, 3-007
**Estimated Hours:** ~40h
**Depends on:** Slices 10, 3 (Category__c taxonomy)

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 3-006 | Actual Revenue with Category Snapshot and Late Flag | 24h |
| 3-007 | Async Projection Rollup | 16h |

### Deliverables
- `Actual_Revenue__c` trigger handler `ActualRevenueTriggerHandler` (E3-C09): canonical pattern in skeleton
- `Category_Snapshot__c` field on `Actual_Revenue__c`: captures category name at record creation; immutable after write
- `Is_Late__c` flag: set when Actual arrives after Period Close (drives Slice 15 lateActualsWorklist routing)
- `ProjectionRollupQueueable` (E3-C10): async rollup of `Actual_Revenue__c` onto `Projection__c`; self-chains for batches >50 Projections
- Lookup (not master-detail) from `Projection__c` to `Advertising_Opportunity__c` preserved for delete-isolation

### Cross-Slice Notes
- `Is_Late__c` flag consumed by Period Close Late Actuals Worklist (Slice 15)
- `Category_Snapshot__c` consumed by Reporting slices (17-20) for historical accuracy

---

## Slice 11b — Reconciliation: Preempt-to-Booked & Forecast Lifecycle

**Branch:** `agent/reconciliation-preempt-forecast`
**Stories:** 3-008, 3-009
**Estimated Hours:** ~88h
**Depends on:** Slices 10, 11a

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 3-008 | Real-Time Preempt-to-Booked Money Movement | 56h |
| 3-009 | Five-Stage Forecast Lifecycle | 32h |

### Deliverables
- `PreemptToBookedEngine` (E3-C08): real-time money movement logic when booked revenue preempts unbooked projections
- Platform event or trigger-based invocation; governor-limit-safe chunking
- Five-stage `Forecast_Stage__c` picklist on `Projection__c`: Unsubmitted → Submitted → Approved → Booked → Closed
- Stage transition validation: locked stages cannot regress without `Period_Close_Admin` permission
- `ForecastLifecycleTriggerHandler`: enforces stage rules; fires `ProjectionRollupQueueable` on stage change

### Cross-Slice Notes
- Forecast stage states consumed by `Period_Close__c` state machine (Slice 14)
- Preempt-to-Booked logic interacts with `Budget_Line__c` (existing object); verify junction integrity with Slice 12

---

## Slice 12 — Forecast: Schema, Budget & Reference Data

**Branch:** `agent/forecast-schema-budget`
**Stories:** 4-001, 4-004, 4-006, 4-007, 4-008
**Estimated Hours:** ~86h
**Depends on:** Slices 2, 3, 11b

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 4-001 | Projection Composite Uniqueness | 16h |
| 4-004 | Account + Category + Revenue Type Annual Budget | 24h |
| 4-006 | Opportunity Layered with Matrix Dimensions | 8h |
| 4-007 | Granular Budget Locking by Market, Office, and Group | 32h |
| 4-008 | Projection Linkage to Pitch Projects | 8h- |

### Deliverables
- `Projection__c.Projection_Composite_Key__c` formula field; unique external ID; `ProjectionTriggerHandler` populates before-insert
- Composite key includes: Account, Category, Revenue Type, Period, AE, Calendar Type
- `Budget__c` (E4-C02): grain is Account + Category + Revenue Type per year (revised per 2026-04-22 transcript); CSV ingest pattern matching pipeline pattern
- `Budget__c.Locked__c` boolean; `Lock_Level__c` picklist (Market/Office/Group); granular locking via `PeriodCloseLockService`
- Opportunity custom fields (E4-C03): `Pursuit_Stage__c`, Matrix dimension lookups; `Projection.Opportunity__c` lookup; both `StageName` and `Pursuit_Stage__c` retained for v1
- `Projection__c.Pitch_Project__c` lookup (see Slice 21 for `Pitch_Project__c` object)

### Cross-Slice Notes
- `Budget__c` schema consumed by Account Budget Grid (Slice 13)
- Locking logic integrates with Period Close (Slice 14)

---

## Slice 13 — Forecast: UI Grids

**Branch:** `agent/forecast-ui-grids`
**Stories:** 4-002, 4-003
**Estimated Hours:** ~92h
**Depends on:** Slices 11a, 12

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 4-002 | AE Projection Grid with Paste-from-Excel | 60h |
| 4-003 | Account Budget vs Projection vs Actual Grid | 32h |

### Deliverables
- LWC `aeProjectionGrid` (E4-C05): 12-column month grid; paste-from-Excel handler in JS (clipboard API); bulk upsert via Apex
- Apex `ProjectionGridController`: bulk `Database.upsert` with per-row `Database.SaveResult` parsing; inline error display
- LWC `accountBudgetGrid` (E4-C06): 12-row aggregated dataset (Budget / Projection / Actual per month)
- Apex `AccountBudgetGridController`: returns aggregated data; variance formula `Projection - Budget`
- Both grids respect Period Close locked status (read-only when period is closed)

---

## Slice 14 — Period Close: Core

**Branch:** `agent/period-close-core`
**Stories:** 5-001, 5-002, 5-003
**Estimated Hours:** ~64h
**Depends on:** Slices 11b, 12

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 5-001 | Period Close State Machine | 16h |
| 5-002 | Period Snapshot at Close | 24h |
| 5-003 | Period Close and Reopen Actions | 24h |

### Deliverables
- `Period_Close__c` (E5-C01): state machine with `Status__c` picklist (Open → Closing → Closed → Reopened)
- Custom permission gating: `Period_Close_Admin` required to close or reopen
- `PeriodCloseService` (close) and `PeriodReopenService` (reopen): permission check + state transition + snapshot trigger
- `Period_Snapshot__c` (E5-C02): immutable snapshot of all `Projection__c` and `Budget__c` records at close; FLS read-only post-create
- `PeriodCloseQueueable` (E5-C03): async snapshot generation for large periods
- LWC `periodCloseActions` (E5-C07): close and reopen buttons with confirmation modal
- Validation rule `No_Edit_Closed_Period` on `Projection__c`

---

## Slice 15 — Period Close: Analytics

**Branch:** `agent/period-close-analytics`
**Stories:** 5-004, 5-005, 5-006
**Estimated Hours:** ~68h
**Depends on:** Slices 11a, 14

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 5-004 | Late Actuals Worklist | 24h |
| 5-005 | Period Close Dashboard | 32h |
| 5-006 | Forecast Accuracy Reports | 12h |

### Deliverables
- LWC `lateActualsWorklist` (E5-C08): surfaces `Actual_Revenue__c` records where `Is_Late__c = true`; AE can accept or reject (Status = Excluded)
- Apex `LateActualsController`
- LWC `periodCloseDashboard` (E5-C10): expected-close date from Custom Setting `Period_Close_Settings__c`; progress indicators per source
- Apex `PeriodCloseDashboardController` with `@AuraEnabled(cacheable=true)`
- Custom Report Type: `Period_Snapshots_with_Account`; 4 starter Forecast Accuracy reports; folder: `Forecast_Accuracy_Reports`

---

## Slice 16 — Sales Ops Console

**Branch:** `agent/sales-ops-console`
**Stories:** 6-001, 6-002, 6-003, 6-004
**Estimated Hours:** ~64h
**Depends on:** Slices 6, 8, 10

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 6-001 | Sales Ops Console Lightning App | 16h |
| 6-002 | Composite KPI Dashboard | 24h |
| 6-003 | Exclusion Log | 8h |
| 6-004 | Source Health Drill-Down | 16h |

### Deliverables
- Lightning App `Sales_Operations_Console` (E6-C09)
- Lightning Page `Sales_Ops_Home` with LWC `salesOpsHomeKpis` (E6-C10)
- Apex `SalesOpsHomeController.getKpis()`: composite fetcher for unmatched records, exclusion counts, staleness flags; threshold values in Custom Setting
- List view `Exclusion_Log` on `Inbound_Staging__c`; `Excluding_Rule__c` field populated by `MappingRuleExecutor`; console tab
- `Source_System__c` record page enhancement: load history chart (lightning-chart or chart.js — decision pending); drill-down to `Load_Batch__c` records

---

## Slice 17 — Reporting: Pacing Snapshots & Forecast Change

**Branch:** `agent/reporting-pacing-snapshots`
**Stories:** 8-001, 8-002
**Estimated Hours:** ~52h
**Depends on:** Slices 11a, 14

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 8-001 | Daily Pacing Snapshot Engine | 40h |
| 8-002 | Forecast Change Reporting (Native + Snapshot Data) | 12h |

### Deliverables
- `Pacing_Snapshot__c` custom object: daily materialized snapshot of booked + projected + budget per Account per Period
- `PacingSnapshotScheduler` (daily Schedulable) + `PacingSnapshotBatch` (chunked Queueable)
- No custom UI — standard list views + native Salesforce reports on `Pacing_Snapshot__c`
- Forecast Change Report: blends current `Projection__c` with `Period_Snapshot__c` historical baseline; native CRT + 2 starter reports

---

## Slice 18 — Reporting: New/Lost/Returning & Reporting Tags

**Branch:** `agent/reporting-new-lost-returning`
**Stories:** 8-003, 8-004
**Estimated Hours:** ~64h
**Depends on:** Slices 11a, 12

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 8-003 | Multi-View New / Lost / Returning Calculation Engine | 40h |
| 8-004 | Reporting Tag Derivation (Political / Advocacy / Media-for-Equity / X-PAD) | 24h |

### Deliverables
- `New_Lost_Returning_Calculation__c` materialized table; `NewLostReturningEngine` nightly Schedulable batch + on-demand Apex API
- Views: by Advertiser, by Agency, by Category; compares current period actuals to prior year
- Standard Salesforce reports on materialized table; no custom LWC grid
- `Reporting_Tag_Rule__mdt` (Custom Metadata Type): rule definitions for Political, Advocacy, Media-for-Equity, X-PAD tags
- `Reporting_Tag_Assignment__c` junction: `Actual_Revenue__c` ↔ `Tag_Name`
- No custom UI — standard list views; tag derivation runs on `Actual_Revenue__c` trigger

---

## Slice 19 — Reporting: Raw Pacing Extract ("The Bible")

**Branch:** `agent/reporting-pacing-extract`
**Stories:** 8-005
**Estimated Hours:** ~50h
**Depends on:** Slices 17, 18, 12

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 8-005 | Raw Pacing Extract Report ("The Bible") | 50h |

### Deliverables
- LWC `pacingExtractRunner`: column picker + date range configurator (NOT a grid display)
- Apex `PacingExtractService.runReport(filters, columns)`: blends today's booked, last-year-final, last-year-pace, change-since-arbitrary-date, weighted forecast, unweighted forecast, budget, and pitch-project rollups
- Output: batch-generated CSV delivered via `ContentVersion` + download link
- Columns are user-configurable via the LWC picker
- Maria T. Espinoza daily analytics use case: single CSV row per Account per Period

---

## Slice 20 — Reporting: Financial Report Builder & Config Pack

**Branch:** `agent/reporting-builder-config`
**Stories:** 8-006, 8-007
**Estimated Hours:** ~80h
**Depends on:** Slices 17, 18, 12, 14

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 8-006 | Build-Your-Own Financial Report Builder | 40h |
| 8-007 | Salesforce Reports & Dashboards Configuration Pack | 40h |

### Deliverables
- Build-Your-Own Financial Report Builder: LWC configurator allowing Sales Ops to select dimensions (Account, Category, Region, Revenue Type, Period) and metrics (Budget, Projection, Actual, Variance)
- Apex backend generates SOQL dynamically; output via native Report or CSV
- Config Pack: 15+ native Salesforce reports across all objects; 3 dashboards (AE Pipeline, Sales Ops Overview, Period Close Status)
- Folder structure: `Matrix_AE_Reports`, `Matrix_SalesOps_Reports`, `Matrix_Exec_Reports`

---

## Slice 21 — Pitch Projects: Core

**Branch:** `agent/pitch-projects-core`
**Stories:** 9-001, 9-002, 9-003
**Estimated Hours:** ~56h
**Depends on:** Slices 9, 11a

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 9-001 | Pitch Project Object with Corporate and Market Ownership | 16h |
| 9-002 | Pitch Project Participating Outlets Junction | 16h |
| 9-003 | Unit Code → Actual Revenue Auto-Link | 24h |

### Deliverables
- `Pitch_Project__c` custom object: Corporate ownership (HoldCo/Agency), Market ownership (Outlet), `Status__c` picklist, `Unit_Code__c` (unique external ID)
- `Pitch_Project_Outlet__c` junction: `Pitch_Project__c` ↔ `Outlet__c`; LWC `pitchProjectOutletPicker` for managing participating outlets
- Unit Code auto-link: `CounterpointTransformer` populates `Unit_Code__c` on `Actual_Revenue__c`; trigger or batch matches `Actual_Revenue__c.Unit_Code__c` → `Pitch_Project__c.Unit_Code__c` and sets `Actual_Revenue__c.Pitch_Project__c` lookup
- Reconciliation honors participating outlets when linking actuals to pitch projects

### Cross-Slice Notes
- `Pitch_Project__c` object must exist before Slice 12 (`Projection__c.Pitch_Project__c` lookup) and Slice 22

---

## Slice 22 — Pitch Projects: UI & Reports

**Branch:** `agent/pitch-projects-ui-reports`
**Stories:** 9-004, 9-005
**Estimated Hours:** ~56h
**Depends on:** Slice 21

### Stories

| ID | Title | Hours |
|----|-------|-------|
| 9-004 | Pitch Project Creation UI | 24h |
| 9-005 | Pitch Project Pacing Report | 32h |

### Deliverables
- Screen Flow `Create_Pitch_Project` + Quick Action on `Pitch_Project__c`; collects Corporate owner, Market owners, participating outlets, unit code
- LWC `pitchProjectPacingReport`: shows booked actuals vs pitch target by participating outlet per period
- Apex `PitchProjectPacingController`: aggregates `Actual_Revenue__c` where `Pitch_Project__c` = current record; compares to `Pitch_Project__c.Target_Revenue__c`

---

## Slice 23 — Phase 2: Deferred Stories (Documentation Only)

**Branch:** `agent/phase-2-deferred`
**Stories:** P2-001, P2-002, P2-003, P2-004, P2-005, P2-006
**Estimated Hours:** Not scoped for Phase 1
**Status:** Document requirements; do not build

### Stories

| ID | Title | Notes |
|----|-------|-------|
| P2-001 | Junction-Split Multi-Category Reports | Requires Slice 3 multi-category junction to be stable first |
| P2-002 | AE Budget Override Workflow | Approval process on `Budget__c`; requires Slice 12 |
| P2-003 | External MDM Platform Integration | Reltio, Informatica MDM, or similar; requires MDM Workspace stable (Slice 4) |
| P2-004 | Outbound Push to WideOrbit | Salesforce → WideOrbit Account + Salesperson sync; requires Slice 9 |
| P2-005 | Recategorize Historical Actuals on Category Change | Back-fill `Category_Snapshot__c` on category restructure; requires Slices 3, 11a |
| P2-006 | Advertiser Self-Service Portal | Experience Cloud portal; requires Slice 2 Account record types |

### Deliverables for this slice
- Detailed solution notes document for each P2 story
- Dependency map showing which Phase 1 slices must be stable before each P2 story can begin
- Rough hour estimates for Phase 2 planning

---

## Summary Table

| Slice | Branch | Stories | Est. Hours | Theme |
|-------|--------|---------|------------|-------|
| 1 | `agent/platform-foundation` | 7-001–7-005 | ~108h | Platform |
| 2 | `agent/mdm-account-hierarchy` | 1-001, 1-002, 1-008, 1-009 | ~44h | MDM |
| 3 | `agent/mdm-category-taxonomy` | 1-003, 1-004 | ~68h | MDM |
| 4 | `agent/mdm-workspace-triage` | 1-005, 1-006, 1-007 | ~62h | MDM |
| 5 | `agent/mdm-reporting-hierarchies` | 1-010, 1-011, 1-012 | ~80h | MDM |
| 6 | `agent/pipeline-core` | 2-001–2-004, 4-005 | ~102h | Pipeline |
| 7 | `agent/pipeline-transformers` | 2-005–2-009 | ~64h | Pipeline |
| 8 | `agent/pipeline-rules-telemetry` | 2-010, 2-011 | ~56h | Pipeline |
| 9 | `agent/reconciliation-matching` | 3-001, 3-002 | ~80h | Reconciliation |
| 10 | `agent/reconciliation-engine-worklists` | 3-003–3-005 | ~104h | Reconciliation |
| 11a | `agent/reconciliation-actuals-rollups` | 3-006, 3-007 | ~40h | Reconciliation |
| 11b | `agent/reconciliation-preempt-forecast` | 3-008, 3-009 | ~88h | Reconciliation |
| 12 | `agent/forecast-schema-budget` | 4-001, 4-004, 4-006–4-008 | ~86h | Forecast |
| 13 | `agent/forecast-ui-grids` | 4-002, 4-003 | ~92h | Forecast |
| 14 | `agent/period-close-core` | 5-001–5-003 | ~64h | Period Close |
| 15 | `agent/period-close-analytics` | 5-004–5-006 | ~68h | Period Close |
| 16 | `agent/sales-ops-console` | 6-001–6-004 | ~64h | Sales Ops |
| 17 | `agent/reporting-pacing-snapshots` | 8-001, 8-002 | ~52h | Reporting |
| 18 | `agent/reporting-new-lost-returning` | 8-003, 8-004 | ~64h | Reporting |
| 19 | `agent/reporting-pacing-extract` | 8-005 | ~50h | Reporting |
| 20 | `agent/reporting-builder-config` | 8-006, 8-007 | ~80h | Reporting |
| 21 | `agent/pitch-projects-core` | 9-001–9-003 | ~56h | Pitch Projects |
| 22 | `agent/pitch-projects-ui-reports` | 9-004, 9-005 | ~56h | Pitch Projects |
| 23 | `agent/phase-2-deferred` | P2-001–P2-006 | deferred | Phase 2 |

**Phase 1 Total: ~1,572 estimated hours across 22 slices**

---

## Critical Cross-Slice Conflicts to Resolve Before Build

1. **`Actual_Revenue__c` vs `Actuals_Record__c`** — two slices reference this object under different names (conv-1777471362030 vs conv-1777470284299). Must resolve to one canonical object name before Slices 7, 11a, or any reporting slice starts.
2. **`CounterpointTransformer` vs `CounterpointIngestionService`** — overlapping Counterpoint parsing logic (conv-1777471362029 vs conv-1777470284299). Must decide: share a base class, or delete one and delegate. Resolve before Slice 7 starts.
3. **`Budget_Line__c` ↔ `Advertising_Opportunity__c`** — existing memory records this as a Lookup (not Master-Detail). Confirm before Slice 12 designs `Budget__c` at Account+Category grain. Existing `Budget_Line__c` may be a different concept from the new `Budget__c` object.
