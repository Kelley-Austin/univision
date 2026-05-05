---
generator: cheese:slice-summary
generatedAt: 2026-05-05T15:35:50.649Z
generatorVersion: 1
---

# Platform Foundation & Master Data Model

## What was done
- Created 5 permission sets at `force-app/main/default/permissionsets/`: `MatrixCore_AE`, `SalesOps_FullAccess`, `MDM_Curator`, `Finance_Analyst`, `Integration_User`.
- Added Account record types `HoldCo`, `Agency`, `Advertiser` under `force-app/main/default/objects/Account/recordTypes/` with validation rule `Enforce_Parent_Hierarchy` to enforce HoldCo → Agency → Advertiser parent linkage.
- Built `Category__c` taxonomy object with fields `Parent_Category__c`, `Is_Active__c`, `Successor_Category__c`, `Description__c`, `Sort_Order__c`, `Level__c`, `Full_Path__c` to support reparenting and lifecycle (retire-with-successor) semantics.
- Added `Account_Category__c` junction object with `Account__c` and `Category__c` lookups to enable many-to-many account categorization.
- Per memory index: slice scope also includes Medium/Outlet/Office reference objects, Projection__c/Budget__c (Private sharing), `categoryTreeManager` LWC, `mdmKpiTiles` LWC, Retire flow, and MDM Workspace App.

## What's pending
- Medium/Outlet/Office reference object metadata, `Projection__c`/`Budget__c` Private sharing config, `categoryTreeManager` LWC, `mdmKpiTiles` LWC, Retire flow, and MDM Workspace Lightning App were not in the captured file list — verify they were committed on `agent/platform-foundation` before the slice is treated as fully landed.
- Account-hierarchy rollup sharing (HoldCo → Agency → Advertiser) needs verification that Private OWD + role-hierarchy access actually delivers the intended visibility.
- Triage resolution UI mentioned in the slice description was not represented in the modified-files list; confirm scope or schedule a follow-up slice.

## Key decisions
- **Account/Projection/Budget set to Private OWD with role-hierarchy rollup** — *Why:* HoldCo/Agency/Advertiser data must be isolated by team while still rolling up to managers; Public Read/Write would leak competitive account data.
- **Three Account record types (HoldCo/Agency/Advertiser) with `Enforce_Parent_Hierarchy` validation** — *Why:* Hierarchy is load-bearing for rollups, reporting, and MDM triage; a validation rule prevents invalid parent links that would corrupt downstream aggregates.
- **`Category__c` uses `Successor_Category__c` for retirement instead of hard-delete** — *Why:* Historical Account_Category__c rows must remain reportable; soft-retire-with-successor preserves audit trail and lets reporting redirect to the replacement node.
- **Five-persona permission-set split rather than profiles** — *Why:* Profiles are 1:1 and brittle; permission sets compose cleanly for the AE/SalesOps/MDM/Finance/Integration matrix and survive future role changes.

## Files changed
- `force-app/main/default/permissionsets/MatrixCore_AE.permissionset-meta.xml`
- `force-app/main/default/permissionsets/SalesOps_FullAccess.permissionset-meta.xml`
- `force-app/main/default/permissionsets/MDM_Curator.permissionset-meta.xml`
- `force-app/main/default/permissionsets/Finance_Analyst.permissionset-meta.xml`
- `force-app/main/default/permissionsets/Integration_User.permissionset-meta.xml`
- `force-app/main/default/objects/Account/recordTypes/HoldCo.recordType-meta.xml`
- `force-app/main/default/objects/Account/recordTypes/Agency.recordType-meta.xml`
- `force-app/main/default/objects/Account/recordTypes/Advertiser.recordType-meta.xml`
- `force-app/main/default/objects/Account/validationRules/Enforce_Parent_Hierarchy.validationRule-meta.xml` — gates the HoldCo → Agency → Advertiser parent chain.
- `force-app/main/default/objects/Category__c/Category__c.object-meta.xml` — taxonomy root supporting drag-to-reparent and retirement.
- `force-app/main/default/objects/Category__c/fields/Parent_Category__c.field-meta.xml`
- `force-app/main/default/objects/Category__c/fields/Is_Active__c.field-meta.xml`
- `force-app/main/default/objects/Category__c/fields/Successor_Category__c.field-meta.xml`
- `force-app/main/default/objects/Category__c/fields/Description__c.field-meta.xml`
- `force-app/main/default/objects/Category__c/fields/Sort_Order__c.field-meta.xml`
- `force-app/main/default/objects/Category__c/fields/Level__c.field-meta.xml`
- `force-app/main/default/objects/Category__c/fields/Full_Path__c.field-meta.xml` — denormalized path enables fast taxonomy lookup in LWC and reports.
- `force-app/main/default/objects/Account_Category__c/Account_Category__c.object-meta.xml` — junction enabling many-to-many account/category mapping.
- `force-app/main/default/objects/Account_Category__c/fields/Account__c.field-meta.xml`
- `force-app/main/default/objects/Account_Category__c/fields/Category__c.field-meta.xml`

## Lessons
- Stand up the permission-set + sharing-model foundation before any business object — sharing changes after data lands force re-share recalculations across millions of rows and risk visibility regressions.
- Use a `Successor_Category__c` self-lookup from day one for any taxonomy you expect to evolve; bolting retire-with-redirect on later requires backfilling every historical junction row.
- Keep a denormalized `Full_Path__c` formula on hierarchical objects — LWC tree components and reports both need readable breadcrumbs and recomputing path via SOQL on every render does not scale.

## Persona impact
This slice serves: MDM Curator, Sales Operations, and Account Executives. Value: Establishes the secure account hierarchy, taxonomy, and permission boundaries that every downstream slice (budgets, opportunities, reconciliation, reporting) depends on.
