# MediaCloud — User Acceptance Test (UAT) Scripts

Step-by-step click-through scripts for testing the front-end of the MediaCloud Salesforce build. Grouped by persona. Use them to demo the system, validate features after a deploy, or onboard new testers.

> **Source of truth:** the metadata in `force-app/main/default`. If a script disagrees with what you see in the org, the org is right and we should update the script.
>
> **Org under test:** `univision-production` (a Developer Edition org, despite the name).
>
> **Date last regenerated:** 2026-05-05.

---

## Section 0 — Before you start (one-time setup)

Do these once per test environment. If you've already done them, skip to Section 1.

### 0.1 Verify what's actually deployed

The repo has a lot of components. Before testing, confirm they're live in the org. Open the org and run each of these checks; if any return `0 records`, that feature isn't deployed yet and the script for it will fail.

```bash
# From the project root, with univision-production as the active org:

# 1. LWCs (expect 23)
sf data query --target-org univision-production -q \
  "SELECT COUNT(Id) FROM LightningComponentBundle WHERE NamespacePrefix = NULL"

# 2. Custom Apps (expect MediaCloud, MDM Workspace, Sales Operations Console)
sf data query --target-org univision-production -q \
  "SELECT DeveloperName, MasterLabel FROM AppDefinition WHERE NamespacePrefix = NULL"

# 3. Custom Tabs
sf data query --target-org univision-production --use-tooling-api -q \
  "SELECT DeveloperName FROM CustomTab WHERE NamespacePrefix = NULL ORDER BY DeveloperName"

# 4. Screen Flows (expect ~17 user-facing + 3 system)
sf data query --target-org univision-production --use-tooling-api -q \
  "SELECT MasterLabel, Status, ProcessType FROM FlowDefinitionView ORDER BY MasterLabel"

# 5. Permission sets (expect 7)
sf data query --target-org univision-production -q \
  "SELECT Name, Label FROM PermissionSet WHERE IsOwnedByProfile = false ORDER BY Name"

# 6. Lightning record/app pages (FlexiPages — expect 11)
sf data query --target-org univision-production --use-tooling-api -q \
  "SELECT DeveloperName, EntityDefinitionId, Type FROM FlexiPage ORDER BY DeveloperName"
```

If anything is missing, deploy via the project's GitHub Actions pipeline (push your branch, open a PR, let the Action handle it — direct `sf project deploy start` against `univision-production` is blocked by deploy policy).

### 0.2 Assign permission sets to your testers

Each persona needs its perm set. Run once per tester:

```bash
sf org assign permset --target-org univision-production --on-behalf-of <username> \
  --name <PermSetName>
```

| Persona | Perm set name | What it unlocks |
|---|---|---|
| Account Executive | `MatrixCore_AE` | Create/manage opportunities, contracts, budget lines, projections; read-only reference data |
| Sales Ops | `SalesOps_FullAccess` | Full CRUD on all Matrix sales objects, account hierarchy, category assignments |
| MDM Curator | `MDM_Curator` | Manage category taxonomy, account hierarchy, reference data (Medium, Outlet, Office) |
| Sales Rep | `Sales_Rep` | Minimum perms for Create Direct Buy Advertiser, Create Agency Account, Link Agency flows |
| Finance Analyst | `Finance_Analyst` | Read-only on budgets, projections, financial objects |
| Integration User (system) | `Integration_User` | API access for Counterpoint ingest pipeline |
| System admin | `LogXAdmin` | Logging framework |

### 0.3 Populate `User.AE_Code__c` on AE testers

The reconciliation worklists and `SalespersonMatcher` filter on this field. Without it, AE testers see an empty list.

Setup → Users → edit user → set `AE Code` field → save. Or via CLI:

```bash
sf data update record --target-org univision-production --sobject User \
  --where "Username='<email>'" --values "AE_Code__c='AE001'"
```

### 0.4 Seed reference data (in this order)

Foreign keys flow downward — create parents first.

1. **Source_System__c** — at least one row per inbound source (e.g. WideOrbit, Counterpoint).
2. **Category__c** — top-level categories first (Local, National, Digital), then children.
3. **Medium__c** — TV, Radio, Digital, OOH.
4. **Outlet__c** — at least one per Medium.
5. **Office__c** — sales offices.
6. **Vehicle__c + Vehicle_Channel__c** — at least one Vehicle with one or more channel junctions.
7. **Account** — create at least one of each record type: HoldCo, Agency, Advertiser, Direct Buy.
8. **Period_Close__c** — one row in `Open` status for the current month.

You can do this through the UI (each object has a custom tab in MediaCloud or MDM Workspace) or with `sf data create record` from the CLI.

### 0.5 Verify custom metadata records

These ship with the repo and drive runtime behavior. Confirm they exist:

```bash
sf data query --target-org univision-production -q \
  "SELECT DeveloperName, Weight__c FROM Forecast_Stage_Weight__mdt"
# Expect 8 rows: NA, Stage_0..Stage_5, Booked

sf data query --target-org univision-production -q \
  "SELECT DeveloperName, Schedule_Hour__c FROM Matrix_Sync_Config__mdt"
# Expect 1 row: Default

sf data query --target-org univision-production -q \
  "SELECT DeveloperName, Source_Code__c FROM Revenue_Code_Mapping__mdt"
# Expect 12 WideOrbit revenue code rows
```

---

## How to read each script

Every script follows the same template:

> - **ID** — short reference (e.g. `AE-03`)
> - **Persona / Perm set** — who's running it
> - **Where** — App → tab/record path the user navigates to
> - **Preconditions** — data that must exist before you start
> - **Steps** — numbered click path
> - **Expected** — what success looks like in the UI
> - **Verify** — a SOQL one-liner or record check that confirms success at the data layer
> - **Cleanup** — what to delete or revert when finished

---

## Section 1 — MDM Curator (`MDM_Curator` perm set, MDM Workspace app)

### MDM-01 · Browse and edit the category taxonomy

- **Where:** App Launcher → "MDM Workspace" → Home tab.
- **Preconditions:** at least 5 `Category__c` records with parent/child relationships seeded.
- **Steps:**
  1. Open MDM Workspace. Default landing is the MDM Workspace Home app page.
  2. Top of page: **MDM KPI Tiles** (`mdmKpiTiles` LWC) — confirm tiles render with category, account, and reference-data counts.
  3. Below that: **Category Tree Manager** (`categoryTreeManager` LWC).
  4. Expand a top-level category by clicking the chevron.
  5. Drag a child category to a different parent.
  6. Confirm the move dialog and accept.
- **Expected:** the tree re-renders with the category in its new parent. Toast: "Category updated."
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Name, Parent_Category__r.Name FROM Category__c WHERE Name = '<child>'"
  ```
- **Cleanup:** drag the category back to its original parent.

### MDM-02 · Retire a category with a successor

- **Where:** MDM Workspace → Category tab → open a Category record → action bar → "Retire Category With Successor" Quick Action.
- **Preconditions:** a `Category__c` you don't mind retiring; another category to receive its assignments; at least one `Account_Category__c` junction pointing at the source category (so you can verify reassignment).
- **Steps:**
  1. Open the source Category record.
  2. Launch the **Retire Category With Successor** Screen Flow (Quick Action on Category record page — note: this Quick Action may need to be configured in Setup if not in repo metadata).
  3. Flow first screen: **"Select Successor Category"** — choose a successor from the picker.
  4. Confirm screen: **"Confirm Retire"** — review counts (related Account_Category junctions, child categories).
  5. Click "Retire."
  6. Final screen: **"Done"** — shows the count of records reassigned.
- **Expected:** Done screen shows non-zero reassignment count if junctions existed.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Status__c, Successor_Category__c FROM Category__c WHERE Id = '<retired-id>'"
  # Status__c = 'Retired', Successor_Category__c = <successor-id>
  ```
- **Cleanup:** revert via Workbench/Data Loader (no in-app un-retire flow).

### MDM-03 · Create an Agency Account

- **Where:** MDM Workspace → Account tab → "New" button → choose record type "Agency", or directly launch the **Create Agency Account** Screen Flow if you've placed it as a Quick Action.
- **Preconditions:** none.
- **Steps:**
  1. Launch flow.
  2. First screen: **"Agency Details"** — fill Agency Name, Market, Primary Contact.
  3. Submit.
  4. Final screen: **"Agency Created"** — link to navigate to the new record.
- **Expected:** new Account with `RecordType.DeveloperName = 'Agency'`.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Name, RecordType.DeveloperName FROM Account WHERE Name = '<agency name>'"
  ```
- **Cleanup:** delete the test Account.

### MDM-04 · Link an Agency to an Advertiser

- **Where:** MDM Workspace → Account tab → open an Advertiser or Direct Buy record → action bar → **"Link Agency"** Quick Action.
- **Preconditions:** at least one Agency Account (from MDM-03) and one Advertiser/Direct Buy Account.
- **Steps:**
  1. Open the Advertiser record.
  2. Click **Link Agency** in the action bar (this is a real Quick Action in the repo: `Link_Agency`, launches `Link_Agency_To_Advertiser` Screen Flow).
  3. Pick the agency.
  4. Confirm.
- **Expected:** `Account.Primary_Agency__c` now points at the agency. The Agency's record page shows the advertiser in its **Managed Advertisers** related list.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Name, Primary_Agency__r.Name FROM Account WHERE Id = '<advertiser-id>'"
  ```
- **Cleanup:** clear `Primary_Agency__c` on the advertiser.

### MDM-05 · Edit a mapping rule

- **Where:** MediaCloud → Source System tab → open a Source System record → scroll to **Mapping Rule Editor**.
- **Preconditions:** at least one `Source_System__c` and one sample `Inbound_Staging__c` row from that source.
- **Steps:**
  1. Open Source System record. The page surfaces (in order): file upload, batch dashboard, **Mapping Rule Editor** (`mappingRuleEditor` LWC), record detail.
  2. Add a new rule (Map or Exclude).
  3. Click "Dry-run preview" and review which staging rows would be affected.
  4. Save.
- **Expected:** new `Mapping_Rule__c` row created; preview shows expected row count.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Source_System__r.Name, Rule_Type__c, Match_Pattern__c FROM Mapping_Rule__c ORDER BY CreatedDate DESC LIMIT 5"
  ```

---

## Section 2 — Sales Rep (`Sales_Rep` perm set, MediaCloud app)

### REP-01 · Create a Direct Buy Advertiser

- **Where:** App Launcher → MediaCloud → Account tab. Launch the **Create Direct Buy Advertiser** Screen Flow (via list-view button or Quick Action — confirm placement in your org).
- **Preconditions:** none.
- **Steps:**
  1. Launch flow.
  2. First screen: **"Advertiser Details"** — fill Name, MDM External ID, Primary Contact, Market.
  3. Submit.
  4. Final screen: **"Account Created"** with link to navigate.
- **Expected:** new Account with `RecordType.DeveloperName = 'Direct_Buy'`.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Name, RecordType.DeveloperName, MDM_External_Id__c FROM Account ORDER BY CreatedDate DESC LIMIT 1"
  ```

### REP-02 · Create a Local Ad Sales Proposal

- **Where:** MediaCloud → Account tab → open an Account → launch **Create Local Ad Proposal** Screen Flow.
- **Preconditions:** at least one `Vehicle__c` and `Vehicle_Channel__c` seeded; a target Account.
- **Steps:**
  1. Launch flow from the Account.
  2. **Step 1 of 2 — Proposal Details** — fill campaign name, dates, budget cap, target audience.
  3. Click Next.
  4. **Step 2 of 2 — Vehicle & Budget Lines** — pick a Vehicle, allocate spots/dollars per line.
  5. Submit.
- **Expected:** an `Opportunity` is created with attached `Budget_Line__c` rows; if VF PDF render is in scope, the proposal PDF link appears.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Name, Account.Name, RecordType.DeveloperName FROM Opportunity WHERE RecordType.DeveloperName = 'Local_Ad_Sales' ORDER BY CreatedDate DESC LIMIT 1"
  ```

### REP-03 · Log a sales activity

- **Where:** MediaCloud → Opportunity record → launch **Log Sales Activity** Screen Flow.
- **Preconditions:** at least one open Opportunity.
- **Steps:**
  1. Open an Opportunity record.
  2. Launch the **Log Sales Activity** flow.
  3. Screen: **"Log Sales Activity"** — choose Activity Type, Activity Date, Outcome, Notes, optional Next Step.
  4. Submit.
  5. Final screen: **"Activity Logged"**.
- **Expected:** a new `Task` is created on the Opportunity. If "Next Step" was entered, `Opportunity.NextStep` is updated.
- **Verify:** related list "Activities" on the Opportunity now shows the task.

---

## Section 3 — Account Executive (`MatrixCore_AE` perm set, MediaCloud app)

### AE-01 · View the AE Projection Grid on an Opportunity

- **Where:** MediaCloud → Opportunity tab → open an Opportunity.
- **Preconditions:** Opportunity exists; ideally with some `Projection__c` rows already.
- **Steps:**
  1. Open the Opportunity. Record page is **Opportunity_Record_Page** — components in order: Highlights → Record Detail → **AE Projection Grid** (`aeProjectionGrid` LWC) → Budget Lines related list → Advertising Contracts related list → **Source File Upload** (`sourceFileUpload` LWC) → other related lists.
  2. In the AE Projection Grid, paste a tab-delimited block from Excel (12 monthly amounts).
  3. Cells validate inline (numbers only, non-negative).
  4. Click Save.
- **Expected:** Projection rows persist with correct `Composite_Key__c` (Account+Year+Month), Total formula updates.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Composite_Key__c, Period_Year__c, Period_Month__c, Projected_Amount__c FROM Projection__c WHERE Opportunity__c = '<opp-id>' ORDER BY Period_Month__c"
  ```

### AE-02 · View the Account Budget Grid

- **Where:** MediaCloud → Account tab → open an **Advertiser** Account.
- **Preconditions:** Account with RecordType = Advertiser; budget data optional.
- **Steps:**
  1. Open the Advertiser Account. Record page is **Account_Advertising_Budget** (assigned to the Advertiser record type) — components in order: Highlights → Record Detail → **Account Budget Grid** (`accountBudgetGrid` LWC) → **AE Reconciliation Worklist** (`aeReconciliationWorklist` LWC) → Budget Lines list → Actual Revenues list → other related lists.
  2. Enter monthly budget amounts in the grid (12 cells).
  3. Save.
- **Expected:** `Budget__c` row created or updated with 12 monthly fields and a Total formula.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Account__r.Name, Total__c, Jan__c, Feb__c FROM Budget__c WHERE Account__c = '<acct-id>'"
  ```

### AE-03 · Reconcile an unmatched staging row from the Account page

- **Where:** open an Advertiser Account → scroll to **AE Reconciliation Worklist**.
- **Preconditions:** at least one `Inbound_Staging__c` row with `Status__c = 'Unmatched'` and `Raw_AE_Code__c = <your AE code>`.
- **Steps:**
  1. Worklist auto-loads paginated unmatched rows for your AE code.
  2. Find a row, click in the Account search box, type the advertiser name.
  3. Pick from the autocomplete (max 10 Advertiser results).
  4. Click **Accept Match**.
- **Expected:** toast "Match accepted." Row disappears from the worklist.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Status__c, Account__r.Name, Match_Account_Tier__c, Match_Account_Method__c FROM Inbound_Staging__c WHERE Id = '<staging-id>'"
  # Status__c='Matched', Match_Account_Method__c='MANUAL_ACCEPT'
  ```

### AE-04 · Exclude an unmatched row

- **Where:** same place as AE-03.
- **Steps:**
  1. Click **Exclude** on a row.
  2. Enter a reason in the dialog.
  3. Confirm.
- **Expected:** row disappears, `Status__c = 'Excluded'`, `Exclusion_Reason__c` populated.

### AE-05 · Create a Pitch Project

- **Where:** MediaCloud → Pitch Project tab → New, or launch **Pitch Project Creator** Screen Flow.
- **Preconditions:** at least one `Vehicle__c` with channels; at least one `Outlet__c`.
- **Steps:**
  1. Launch the flow.
  2. Single screen: **"Create Pitch Project"** (renders the `pitchProjectCreatorCmp` LWC inline) — fill name, advertiser, target spend, dates, then pick Outlets to participate.
  3. Submit.
- **Expected:** `Pitch_Project__c` row + `Pitch_Project_Outlet__c` junctions for each picked outlet.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Name, (SELECT Id, Outlet__r.Name FROM Pitch_Project_Outlets__r) FROM Pitch_Project__c ORDER BY CreatedDate DESC LIMIT 1"
  ```

### AE-06 · Track pitch pacing

- **Where:** open a Pitch Project record.
- **Steps:**
  1. Record page is **Pitch_Project_Record_Page** — Highlights → Record Detail → **Pitch Project Pacing** (`pitchProjectPacing` LWC) → related lists.
  2. Confirm pacing chart renders (pacing % vs. days elapsed).
- **Expected:** pacing bar reflects actual spend / target.

### AE-07 · Promote an Opportunity to a Contract

- **Where:** Opportunity record → action bar → **Promote Opportunity to Contract** (Screen Flow Quick Action — verify placement).
- **Preconditions:** Opportunity in advanced stage with Budget Lines.
- **Steps:**
  1. Open Opportunity, click the Quick Action.
  2. Confirm screen — flow validates required fields.
  3. Submit.
- **Expected:** new `Advertising_Contract__c` (Master-Detail to the Opportunity) with Budget Lines copied.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Name, Opportunity__r.Name, Status__c FROM Advertising_Contract__c WHERE Opportunity__c = '<opp-id>'"
  ```

### AE-08 · Upload source actuals on an Opportunity

- **Where:** Opportunity record → scroll to **Source File Upload** (`sourceFileUpload` LWC).
- **Preconditions:** at least one `Source_System__c` configured; sample CSV file matching the source's expected format.
- **Steps:**
  1. Pick the source from the dropdown.
  2. Choose CSV file.
  3. Upload.
- **Expected:** a new `Load_Batch__c` row is created; rows appear in `Inbound_Staging__c`.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Source_System__r.Name, Status__c, Row_Count__c FROM Load_Batch__c ORDER BY CreatedDate DESC LIMIT 1"
  ```

---

## Section 4 — Sales Ops (`SalesOps_FullAccess`, Sales Operations Console app)

### OPS-01 · Open the Sales Ops Console

- **Where:** App Launcher → "Sales Operations Console". Default landing is the **Sales Ops Console** tab.
- **Steps:**
  1. The Console tab renders the **`salesOpsConsole` LWC** which contains six sub-tabs and a KPI header.
  2. Confirm KPI header loads (pacing weighted forecast, budget, variance).
- **Expected:** sub-tab nav appears (KPI Dashboard, Bible Extract, Reconciliation Worklist, Late Actuals, Exclusion Log, Financial Report Builder — names may vary slightly).

### OPS-02 · KPI Dashboard

- **Where:** Console → KPI Dashboard sub-tab → renders `salesOpsKpiDashboard` LWC.
- **Steps:**
  1. Pick a period year.
  2. Inspect the pacing roll-up.
- **Expected:** weights come from `Forecast_Stage_Weight__mdt` records (Booked × 1.0, Stage_5 × 0.85, Stage_4 × 0.6, etc.) — not hardcoded.
- **Verify:** open `Forecast_Stage_Weight__mdt` records in Setup and confirm the weights match what the dashboard displays.

### OPS-03 · Bible Extract

- **Where:** Console → Bible Extract sub-tab → renders `bibleExtract` LWC.
- **Steps:**
  1. Apply year filter.
  2. Confirm column order: Booked / Last Year / Forecast / Budget.
  3. Click "Export."
- **Expected:** CSV download with totals matching raw `Actual_Revenue__c` + `Budget__c` data.

### OPS-04 · Sales Ops Reconciliation Worklist

- **Where:** Console → Reconciliation sub-tab → renders `salesOpsReconciliationWorklist` LWC.
- **Steps:**
  1. Multi-filter: AE Code, Source System, Period Month, Period Year.
  2. Click Search.
  3. Select multiple rows via checkbox.
  4. Click **Bulk Exclude** → enter reason → confirm.
  5. Click **Run Reconciliation Batch** → toast shows AsyncApexJob ID.
- **Expected:** excluded rows leave the list; batch is queued.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, JobType, ApexClass.Name, Status FROM AsyncApexJob WHERE ApexClass.Name = 'ReconciliationBatch' ORDER BY CreatedDate DESC LIMIT 1"
  ```

### OPS-05 · Late Actuals Worklist

- **Where:** Console → Late Actuals sub-tab → `lateActualsWorklist` LWC.
- **Preconditions:** at least one closed `Period_Close__c` and at least one `Actual_Revenue__c` arriving after the close.
- **Steps:**
  1. Worklist surfaces all rows where `Is_Late__c = true`.
- **Expected:** late rows appear with reason text.

### OPS-06 · Exclusion Log

- **Where:** Console → Exclusion Log sub-tab → `exclusionLogListView` LWC.
- **Steps:** spot-check that excluded rows show reason and excluder.

### OPS-07 · Financial Report Builder

- **Where:** Console → Financial Report Builder sub-tab → `financialReportBuilder` LWC.
- **Steps:**
  1. Pick a date range and grouping.
  2. Run.
  3. Export.

### OPS-08 · Run a Period Close

- **Where:** MediaCloud or Sales Operations Console → Period Close tab → open a `Period_Close__c` record.
- **Preconditions:** a `Period_Close__c` row in `Open` status; some Projections and Actuals for that period.
- **Steps:**
  1. Record page is **Period_Close_Record_Page** — Highlights → Record Detail → **Period Close Dashboard** (`periodCloseDashboard` LWC) → **Period Close Actions** (`periodCloseActions` LWC) → **Late Actuals Worklist** (`lateActualsWorklist` LWC) → related lists.
  2. In **Period Close Actions**, click "Close Period" → confirm.
  3. (Or launch the **Period Close Actions** Screen Flow from a Quick Action — single screen labeled "Period Close Actions" that wraps the same Apex.)
- **Expected:** Status flips Open → Closed. `Period_Snapshot__c` rows are created (one per dimension snapshotted). Reopening blocked if a later period is already closed.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Status__c, (SELECT Id, Variance_Pct__c FROM Period_Snapshots__r) FROM Period_Close__c WHERE Id = '<id>'"
  ```

### OPS-09 · Run reconciliation from a Quick Action

- **Where:** Opportunity (or Advertising_Contract) record → action bar → **Run Reconciliation** Screen Flow Quick Action.
- **Preconditions:** matching `Inbound_Staging__c` rows exist.
- **Steps:**
  1. Launch the flow.
  2. Confirm screen labeled **"Run Reconciliation"** — review what will run.
  3. Click Run.
  4. Branch on result:
     - Success → screen **"Reconciliation Queued"** with the AsyncApexJob ID.
     - Error → screen **"Error"** with the failure reason.
- **Verify:** AsyncApexJob row exists.

---

## Section 5 — Traffic Coordinator (scope-flagged)

> ⚠️ **Out of SOW Phase 1 — DO NOT test against any real callout endpoint without a Change Order.** The build is present so you can verify the in-org behavior, but `TrafficOrderTransmitQueueable` should not actually transmit.

### TR-01 · Enter traffic copy on a Budget Line

- **Where:** MediaCloud → Budget Line tab → open a record → action bar → **Traffic Copy Entry** Quick Action.
- **Steps:**
  1. Launch the **Traffic Copy Entry** Screen Flow.
  2. Fill copy fields (6 of them — ISCI, headline, body, etc.) and traffic status.
  3. Submit.
- **Expected:** Budget Line traffic-status and copy fields update.

### TR-02 · Make-good / cancellation

- **Where:** Advertising_Contract record → action bar → **Make-Good or Cancellation** Quick Action.
- **Steps:** launch the **Makegood_Or_Cancellation** Screen Flow, follow its screens.
- **Expected:** policy fields update on the contract. Underlying Apex (`CancellationPolicyService`) computes credit memo amounts.

### TR-03 · Matrix Inventory Admin Sync

- **Where:** Setup → Flows → run the **Matrix Inventory Admin Sync** Screen Flow manually (this is a Flow, not a Quick Action).
- **Steps:**
  1. Launch flow. First screen: **"Matrix Sync Status"** — shows last sync time, current schedule.
  2. Pick a User Action: **"Trigger Now"** or change schedule.
  3. If Trigger Now: screen **"Sync Queued"**.
  4. If reschedule: **"Change Schedule Time"** → **"Schedule Updated"**.
- **Expected:** `Matrix_Sync_Log__c` row created on each manual run.
- **Verify:**
  ```bash
  sf data query --target-org univision-production -q \
    "SELECT Id, Status__c, Trigger_Source__c, Records_Synced__c FROM Matrix_Sync_Log__c ORDER BY CreatedDate DESC LIMIT 1"
  ```

---

## Section 6 — Finance Analyst (`Finance_Analyst`, read-only)

### FIN-01 · Inspect a Period Close

- **Where:** MediaCloud → Period Close tab → open a record.
- **Steps:** view-only access — confirm dashboard renders, Period_Snapshot__c history visible, no edit buttons.
- **Verify:** attempting to edit fields prompts a permission error.

### FIN-02 · Review load batch history

- **Where:** MediaCloud → Source System tab → open a record → **Load Batch Dashboard** (`loadBatchDashboard` LWC).
- **Steps:** scan recent batches by status (Success / Errors). Drill into an errored batch to see the rejection reasons.

---

## Section 7 — Cross-cutting / system

### SYS-01 · Logging

- **Where:** Setup → custom tab "Log" (object `Log__c`).
- **Preconditions:** `LogXAdmin` perm set assigned.
- **Steps:**
  1. Trigger any inbound ingest (REP, AE, or OPS scripts above).
  2. Navigate to Log tab.
  3. List view "PlanviewInt" filters to integration logs.
  4. Click into a log → standard record page (with `Log Detail` related list).
- **Expected:** new `Log__c` and `LogDetail__c` rows for each ingest event.

### SYS-02 · System flows (do not trigger directly)

These are AutoLaunched and run on triggers — listed for awareness:

- **Create_Contract_On_Close_Won** — runs on Opportunity stage = Closed Won.
- **Matrix_Order_Outbound_Sync** — runs on Advertising_Contract status changes (Closed Lost → CANCEL, Approved/Closed Won → CREATE/UPDATE). Publishes a platform event.
- **Transmit_Traffic_Order_on_Contract_Activation** — out of SOW; should not fire.
- **LogX_Flow** — system, inserts Log records.

To verify these fired, check the affected records and the Log tab.

---

## Section 8 — Known gaps (don't waste time testing these)

Per project memory and `CLAUDE.md`:

1. **Traffic outbound callout** (`TrafficOrderTransmitQueueable`) — out of SOW Phase 1. Build is present but should not actually transmit.
2. **Make-good / cancellation flow** — built but flagged out of SOW.
3. **Epic 9 data migration** — not started. No migration scripts to test.
4. **Preempt-to-Booked & Forecast Lifecycle** — specs only as of 2026-05-04. No implementation.
5. **Quick Actions in metadata:** only `Account.Link_Agency` is in the repo. Other Quick Actions referenced in FlexiPage descriptions (Make-Good, Period Close Actions, Traffic Copy Entry, Run Reconciliation, Pitch Project Creator) are **not in repo metadata** — they're either Setup-configured directly in the org or not yet built. If they don't appear in your action bar, that's why; flag for the team.
6. **Custom record pages without LWCs:** `Advertising_Contract_Record_Page` and `Budget_Line_Record_Page` ship with only standard components — they rely on Quick Actions for behavior. If those Quick Actions aren't configured (point 5), the pages will look bare.

---

## Appendix A — File map (where each persona's UI lives in the repo)

| Persona | App | Record/App page (FlexiPage) | LWCs surfaced | Screen Flows |
|---|---|---|---|---|
| MDM Curator | MDM Workspace | `MDM_Workspace_Home`, `Agency_Account_Record_Page` | `mdmKpiTiles`, `categoryTreeManager` | `Create_Agency_Account`, `Create_Direct_Buy_Advertiser`, `Link_Agency_To_Advertiser`, `Retire_Category_With_Successor` |
| Sales Rep | MediaCloud | (standard pages) | — | `Create_Direct_Buy_Advertiser`, `Create_Agency_Account`, `Create_Local_Ad_Proposal`, `Log_Sales_Activity`, `Create_Opportunity`, `New_Opportunity`, `Update_Opportunity_Stage` |
| Account Executive | MediaCloud | `Opportunity_Record_Page`, `Account_Advertising_Budget`, `Pitch_Project_Record_Page`, `Advertising_Contract_Record_Page`, `Budget_Line_Record_Page` | `aeProjectionGrid`, `accountBudgetGrid`, `aeReconciliationWorklist`, `pitchProjectCreator`, `pitchProjectPacing`, `sourceFileUpload`, `proposalBudgetLines`, `budgetLineEditor` | `Pitch_Project_Creator`, `Promote_Opportunity_to_Contract`, `Traffic_Copy_Entry` |
| Sales Ops | Sales Operations Console | `Sales_Operations_Console_App`, `Period_Close_Record_Page`, `Source_System_Record_Page` | `salesOpsConsole`, `salesOpsKpiDashboard`, `bibleExtract`, `salesOpsReconciliationWorklist`, `lateActualsWorklist`, `exclusionLogListView`, `financialReportBuilder`, `periodCloseDashboard`, `periodCloseActions`, `loadBatchDashboard`, `mappingRuleEditor`, `fileUploadSource` | `Period_Close_Actions`, `Run_Reconciliation`, `Matrix_Inventory_Admin_Sync` |
| Finance Analyst | MediaCloud | (read-only on the above) | — | — |

---

## Appendix B — How to update this doc

When new components or flows ship, update this file the same day. The cheapest way to keep it accurate:

1. After a deploy, run the queries in Section 0.1 and diff against this doc.
2. For each new LWC, find its FlexiPage in `force-app/main/default/flexipages/*.flexipage-meta.xml` and add a script.
3. For each new Screen Flow, read its `<screens>` labels and reflect them in the script's "Steps" section.

If a script breaks during testing, do not edit the org to make it match — edit the script (or fix the build, if the regression is real).
