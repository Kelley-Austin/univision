---
generator: cheese:personas
generatedAt: 2026-05-05T15:37:23.576Z
generatorVersion: 1
---

# Personas

## Account Executive (AE)
- **Profile:** [needs input]
- **Permission sets:** MatrixCore_AE, Sales_Rep
- **Role hierarchy:** CEO > VP Sales > Market Sales Manager > Account Executive
- **Apps used:** Sales Cloud, MediaCloud (custom)
- **Data visibility:** Owner-only on Account/Projection/Budget with role-hierarchy rollup to managers (Private OWD); sees their own pipeline, projections, and reconciled actuals.
- **Daily tasks:** Enter and update monthly revenue projections in the AE Projection Grid; create and progress Opportunities through the sales stages; build budget lines and pitch projects for assigned accounts; resolve unmatched revenue items in the AE worklist.
- **Pain points:** Manual reconciliation of actual revenue against projections across five disparate billing systems; no single view of pacing vs. budget vs. last year; pitch tracking lived in spreadsheets disconnected from the deal record.
- **Slices that serve this persona:**
  - Forecast Management & Budget Tracking
  - Reconciliation & Actual Revenue Engine
  - Pitch Projects Module
  - Local Ad Sales Proposal Flow / Budget Planning UI Flow
  - CRM Workflows — Full Sales Cycle
  - Preempt Transition Service
  - Sales Performance Reporting & Dashboard Suite
  - Lightning App Record Pages & Navigation Assembly

## Sales Operations Analyst
- **Profile:** [needs input]
- **Permission sets:** SalesOps_FullAccess
- **Role hierarchy:** CEO > VP Sales > Sales Operations Manager > Sales Operations Analyst; [needs input]
- **Apps used:** Sales_Operations_Console (custom Lightning App), Sales Cloud
- **Data visibility:** Cross-market visibility into all Opportunities, Pacing_Snapshot__c, Period_Close__c, Inbound_Staging__c, Reconciliation_Line__c, and Exclusion Log records.
- **Daily tasks:** Monitor nightly load batches and reconciliation results across all five source systems; manage period close lifecycle (Open → Closed → Reopened) and review variance snapshots; produce 'The Bible' weighted-forecast extract for leadership; triage MDM queue and exclusion log entries.
- **Pain points:** No state machine governing month-end close (reopens were ad-hoc and untraceable); weighted forecast (Won×1.0/Committed×0.6/Pitched×0.3/Working×0.1) calculated manually in spreadsheets; pacing visibility required pulling from multiple sources and reconciling by hand.
- **Slices that serve this persona:**
  - Sales Operations Console & Reporting Analytics
  - Period Close Lifecycle & Variance Reporting
  - Pipeline Ingestion Layer — 5 Source Transformers
  - Reconciliation & Actual Revenue Engine
  - Forecast Management & Budget Tracking
  - Internal Action Items Triage & Cutover Sync
  - Sales Performance Reporting & Dashboard Suite

## Sales Manager / Market Sales Manager
- **Profile:** [needs input]
- **Permission sets:** MatrixCore_AE, Sales_Rep; [needs input] for manager-tier access
- **Role hierarchy:** CEO > VP Sales > Market Sales Manager
- **Apps used:** Sales Cloud, MediaCloud (custom)
- **Data visibility:** Role-hierarchy rollup over their AEs' Accounts, Projections, Budgets, Opportunities, and pacing data within their assigned market(s).
- **Daily tasks:** Review team pacing against budget on the Sales_Manager_Dashboard; approve or coach AE projections at month-start; monitor pitch projects and pipeline health (30/60/90-day); approve cancellations and make-good credits per policy.
- **Pain points:** Could not see consolidated AE pacing without spreadsheet exports; pitch projects and pipeline coverage tracked in disconnected tools; cancellation and make-good approvals lacked an auditable workflow.
- **Slices that serve this persona:**
  - Sales Performance Reporting & Dashboard Suite
  - Forecast Management & Budget Tracking
  - Pitch Projects Module
  - Make Good & Cancellation Request Workflow
  - Period Close Lifecycle & Variance Reporting
  - Preempt Transition Service

## Traffic Coordinator
- **Profile:** [needs input]
- **Permission sets:** Traffic_Coordinator
- **Role hierarchy:** [needs input] > Traffic Operations Lead > Traffic Coordinator
- **Apps used:** MediaCloud (custom), Sales Cloud
- **Data visibility:** Read/edit access to Advertising_Contract__c, Budget_Line__c, Vehicle__c, Vehicle_Channel__c, Matrix_Sync_Log__c across all markets they support.
- **Daily tasks:** Enter spot-level traffic and copy details (Copy_Code__c, Copy_Rotation__c, Spot_Length__c, Weekly_Spots__c, Spot_Instructions__c) on Budget Lines; submit/transmit traffic orders via the Screen Flow quick action; reconcile inventory linkage between Matrix Ad Space IDs and Vehicle__c records; investigate Matrix sync failures in the audit log.
- **Pain points:** Copy and traffic details re-keyed into separate traffic systems; no audit trail when inventory IDs drifted between Matrix and Salesforce; outbound traffic transmission status was opaque.
- **Slices that serve this persona:**
  - Traffic Copy Entry & Order Transmission Flow
  - Matrix API Inventory Sync & Media Plan Linkage
  - Matrix Inventory Sync — Vehicle & Media Plan IDs
  - Make Good & Cancellation Request Workflow

## MDM Curator / Data Steward
- **Profile:** [needs input]
- **Permission sets:** MDM_Curator
- **Role hierarchy:** [needs input] > Data Governance Lead > MDM Curator
- **Apps used:** MDM Workspace (custom Lightning App), Sales Cloud
- **Data visibility:** Full read/edit on Account (all record types), Category__c, Account_Category__c, Source_System__c, Mapping_Rule__c, and the manual-match queue from reconciliation.
- **Daily tasks:** Resolve manual-match queue items from AccountMatcher tier 3; maintain Category__c hierarchy via the categoryTreeManager LWC drag-to-reparent; create and merge HoldCo/Agency/Advertiser records; tune Mapping_Rule__c overrides for source-system field mappings.
- **Pain points:** Account duplicates across HoldCo/Agency/Advertiser hierarchies caused mis-attributed revenue; no central category taxonomy meant inconsistent reporting; ingest field-mapping changes required code deploys before this layer existed.
- **Slices that serve this persona:**
  - Platform Foundation Slice (MDM Workspace, Account record types, Category taxonomy)
  - Reconciliation & Actual Revenue Engine
  - Field Manifest Reconciliation Against Standard Opportunity
  - Pipeline Ingestion Layer — 5 Source Transformers

## Sales Rep (General / Direct Buy)
- **Profile:** [needs input]
- **Permission sets:** Sales_Rep
- **Role hierarchy:** CEO > VP Sales > Market Sales Manager > Sales Rep
- **Apps used:** Sales Cloud
- **Data visibility:** Owner-only with role-hierarchy rollup; can create new Advertiser and Agency Accounts but limited edit access on shared MDM data.
- **Daily tasks:** Create new Direct_Buy Advertiser accounts and Agency accounts via Screen Flow quick actions; link agencies to advertisers via Primary_Agency__c; log activities and progress new opportunities; submit local ad sales proposals.
- **Pain points:** Account creation previously required submitting a ticket to MDM; no guided flow for the Direct_Buy advertiser type; proposal generation lived outside Salesforce.
- **Slices that serve this persona:**
  - Advertiser & Agency Account Flows (Direct_Buy + Agency)
  - Local Ad Sales Proposal Flow Slice
  - CRM Workflows — Full Sales Cycle

## Salesforce Administrator / Developer
- **Profile:** System Administrator
- **Permission sets:** [needs input] (admin-tier; not one of the five canonical persona permsets)
- **Role hierarchy:** [needs input]
- **Apps used:** Setup, Sales_Operations_Console, MDM Workspace, MediaCloud
- **Data visibility:** Modify All Data; full visibility across all custom and standard objects.
- **Daily tasks:** Maintain Cutover.csv for manual Setup steps; deploy slice branches via git push (production) or `sf` CLI (sandboxes); manage Forecast_Stage_Weight__mdt / Matrix_Sync_Config__mdt tuning; investigate batch and queueable failures in Matrix_Sync_Log__c and audit objects.
- **Pain points:** Production deploys previously bypassed source control; field manifest drift between standard Opportunity and the deleted Advertising_Opportunity__c needed reconciliation; no consolidated cutover checklist for non-metadata steps.
- **Slices that serve this persona:**
  - Field Manifest Reconciliation Against Standard Opportunity
  - Internal Action Items Triage & Cutover Sync
  - Solution Design Document v1.0 Gap Closure
  - Internal Meeting Notes → Decision Log Extraction
  - Lightning App Record Pages & Navigation Assembly
