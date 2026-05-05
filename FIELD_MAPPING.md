# Migration Spec: `Advertising_Opportunity__c` → standard `Opportunity`

**Branch:** `agent/migrate-to-standard-opportunity`
**Goal:** Eliminate `Advertising_Opportunity__c` entirely; rebuild on standard `Opportunity`.
**Audience:** Subagents executing the migration. This file is the single source of truth.

---

## Field mapping

For each Advertising_Opportunity__c field, exactly ONE of:
- **MAP**: replace all references with the listed standard Opportunity field (no new custom field needed).
- **PORT**: create the field as a custom field on `Opportunity` (same API name).
- **DROP**: delete with no replacement (use a standard alternative).

| Source field | Action | Target | Notes |
|---|---|---|---|
| `Account__c` (lookup→Account) | MAP | `AccountId` | Standard Opportunity has `AccountId` |
| `Close_Date__c` (date) | MAP | `CloseDate` | Standard, required |
| `Status__c` (picklist) | MAP | `StageName` | Standard, required. Carry over picklist values verbatim. |
| `Estimated_Revenue__c` (currency) | MAP | `Amount` | Standard |
| `Probability__c` (percent) | MAP | `Probability` | Standard |
| `Description__c` (long text) | MAP | `Description` | Standard |
| `Lead_Source__c` (picklist) | MAP | `LeadSource` | Standard |
| `Next_Step__c` (text) | MAP | `NextStep` | Standard |
| `Fiscal_Year__c` (number) | DROP | use auto `FiscalYear` | Standard Opportunity computes fiscal year |
| `Name` (AutoNumber `AO-{0000000}`) | DROP + replace | add custom `Opportunity_Number__c` autonumber `AO-{0000000}` | Standard `Name` becomes manual text; autonumber is preserved as a custom field |
| `Agency_Account__c` (lookup→Account) | PORT | `Opportunity.Agency_Account__c` | |
| `Market__c` (picklist) | PORT | `Opportunity.Market__c` | |
| `Media_Type__c` (picklist) | PORT | `Opportunity.Media_Type__c` | |
| `Start_Date__c` (date) | PORT | `Opportunity.Start_Date__c` | |
| `End_Date__c` (date) | PORT | `Opportunity.End_Date__c` | |
| `Total_Budget__c` (currency/formula) | PORT | `Opportunity.Total_Budget__c` | Preserve formula if any |
| `Total_Actual_Amount__c` | PORT | `Opportunity.Total_Actual_Amount__c` | |
| `Total_Planned_Amount__c` | PORT | `Opportunity.Total_Planned_Amount__c` | |
| `Total_Variance_Amount__c` | PORT | `Opportunity.Total_Variance_Amount__c` | |
| `Matrix_Order_ID__c` | PORT | `Opportunity.Matrix_Order_ID__c` | |
| `Matrix_Sync_Status__c` | PORT | `Opportunity.Matrix_Sync_Status__c` | |
| `Matrix_Sync_Error__c` | PORT | `Opportunity.Matrix_Sync_Error__c` | |
| `Matrix_Last_Synced__c` | PORT | `Opportunity.Matrix_Last_Synced__c` | |
| `Media_Cloud_Media_Plan_ID__c` | PORT | `Opportunity.Media_Cloud_Media_Plan_ID__c` | |
| `Pitch_Project__c` (lookup→Pitch_Project__c) | PORT | `Opportunity.Pitch_Project__c` | |
| `Primary_Contact__c` (lookup→Contact) | PORT | `Opportunity.Primary_Contact__c` | Standard Opp doesn't have ContactId |
| `Primary_Demo__c` | PORT | `Opportunity.Primary_Demo__c` | |
| `Secondary_Demo__c` | PORT | `Opportunity.Secondary_Demo__c` | |
| `Competition__c` | PORT | `Opportunity.Competition__c` | |
| `Proposal_Notes__c` | PORT | `Opportunity.Proposal_Notes__c` | |
| `Lost_Reason__c` | PORT | `Opportunity.Lost_Reason__c` | |

## Record types

Port verbatim under `force-app/main/default/objects/Opportunity/recordTypes/`:
- `Agency_Buy.recordType-meta.xml`
- `Direct_Buy.recordType-meta.xml`
- `Local_Ad_Sales.recordType-meta.xml`

## Apex `SObject` rewrites

In every `.cls` and `.cls-meta.xml`:
- `Advertising_Opportunity__c` → `Opportunity`
- `Advertising_Opportunity__c.SObjectType` → `Opportunity.SObjectType`
- `new Advertising_Opportunity__c(...)` → `new Opportunity(...)`
- `List<Advertising_Opportunity__c>` → `List<Opportunity>`
- Field references: apply the mapping table above. Examples:
  - `opp.Account__c` → `opp.AccountId`
  - `opp.Close_Date__c` → `opp.CloseDate`
  - `opp.Status__c` → `opp.StageName`
  - `opp.Estimated_Revenue__c` → `opp.Amount`
  - `opp.Probability__c` → `opp.Probability`
  - `opp.Description__c` → `opp.Description`
  - `opp.Lead_Source__c` → `opp.LeadSource`
  - `opp.Next_Step__c` → `opp.NextStep`
  - `opp.Fiscal_Year__c` → `opp.FiscalYear` (read-only — drop assignments)
  - PORT fields keep the same API name (no Apex change needed for those)
- SOQL: `[SELECT Id FROM Advertising_Opportunity__c]` → `[SELECT Id FROM Opportunity]`
- Trigger context: `Trigger.new` typed as `List<Opportunity>`
- Test data factories: replace `new Advertising_Opportunity__c(...)` with `new Opportunity(Name='...', StageName='...', CloseDate=..., AccountId=...)`. Note: `Name`, `StageName`, `CloseDate` are required on standard Opp.

## Required fields on standard Opportunity (test data must populate)

- `Name` (required text)
- `StageName` (required picklist)
- `CloseDate` (required date)

If existing test factories omit any, add them.

## Relationship repoints (child objects)

- `Advertising_Contract__c.Advertising_Opportunity__c` field (Master-Detail) → rename to `Opportunity__c` and change `referenceTo` to `Opportunity`. **Keep as Master-Detail.**
- `Budget_Line__c.Advertising_Opportunity__c` (Lookup) → rename to `Opportunity__c`, `referenceTo` → `Opportunity`.
- `Reconciliation_Line__c.Advertising_Opportunity__c` (Lookup) → rename to `Opportunity__c`, `referenceTo` → `Opportunity`.

## Flows / Quick Actions / FlexiPage / Tab

- All 6 flows referencing `Advertising_Opportunity__c` → rewrite object reference to `Opportunity`. Field references follow mapping table.
- Quick actions on `Advertising_Opportunity__c.*` → recreate as `Opportunity.*` (5 actions: Log_Activity, New_Opportunity, Promote_to_Contract, Run_Reconciliation, Update_Stage).
- FlexiPage `Advertising_Opportunity_Record_Page` → recreate as `Opportunity_Record_Page` targeting `Opportunity`.
- Tab `Advertising_Opportunity__c.tab-meta.xml` → DELETE (standard Opportunity tab already exists).
- Account quick action `Create_Advertising_Opportunity` → repoint to create standard Opportunity.

## Reports

All 16 reports + 1 custom report type `Budget_Lines_with_Opportunity_and_Vehicle` → repoint `<reportType>` from custom report-type or `Advertising_Opportunity__c` to `Opportunity`-based equivalents. Field column references follow mapping table.

## Permission sets

3 perm sets (`SalesOps_FullAccess`, `MatrixCore_AE`, `Integration_User`):
- Remove all `<objectPermissions>` and `<fieldPermissions>` entries naming `Advertising_Opportunity__c` or `Advertising_Opportunity__c.*`.
- Add equivalent entries for `Opportunity` and the new ported custom fields.

## Other references

- `Matrix_Order_Sync__e.Opportunity_Id__c` (platform event field) — keep field name; it's already `Opportunity_Id__c`. No change.
- Approval process `Advertising_Contract__c.Contract_Approval_Process` — references master record's parent. May need rewording if it dereferences `Advertising_Opportunity__c`. Audit and update.
- LWC `sourceFileUpload.js-meta.xml` — references object in target list. Update to `Opportunity`.
- `applications/MediaCloud.app-meta.xml` — replace tab references.

## Deletions (final wave)

- `force-app/main/default/objects/Advertising_Opportunity__c/` (entire folder)
- `force-app/main/default/tabs/Advertising_Opportunity__c.tab-meta.xml`
- `force-app/main/default/flexipages/Advertising_Opportunity_Record_Page.flexipage-meta.xml` (after replacement is in place)
- `force-app/main/default/quickActions/Advertising_Opportunity__c.*.quickAction-meta.xml` (5 files)
- Add to `manifest/destructiveChanges.xml` for org-side cleanup.

## Acceptance criteria

`grep -r "Advertising_Opportunity__c" force-app/` returns ZERO matches.
