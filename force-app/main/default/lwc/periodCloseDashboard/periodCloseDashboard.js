import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getTrailing24Months   from '@salesforce/apex/PeriodCloseController.getTrailing24Months';
import getSnapshotsForPeriod from '@salesforce/apex/PeriodCloseController.getSnapshotsForPeriod';

const MONTH_NAMES = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

export default class PeriodCloseDashboard extends LightningElement {

    @track rows = [];
    @track isLoading  = false;
    @track hasError   = false;
    @track errorMessage = '';

    // Drill-down state
    @track showDrilldown       = false;
    @track isDrilldownLoading  = false;
    @track drilldownRows       = [];
    @track drilldownPeriodLabel = '';
    _drilldownPeriodCloseId    = null;

    // ── Wire: trailing 24 months ──────────────────────────────────────────────

    _wiredResult;

    @wire(getTrailing24Months)
    wiredMonths(result) {
        this._wiredResult = result;
        this.isLoading = false;
        const { error, data } = result;
        if (error) {
            this.hasError = true;
            this.errorMessage = error.body?.message || 'Failed to load dashboard data.';
            this.rows = [];
        } else if (data) {
            this.hasError = false;
            this.rows = data.map(r => this._enrichRow(r));
        }
    }

    // ── Row enrichment ────────────────────────────────────────────────────────

    _enrichRow(r) {
        const monthName  = MONTH_NAMES[r.periodMonth] || r.periodMonth;
        const statusBadgeClass = this._badgeClass(r.status);
        const hasSnapshots  = r.snapshotCount != null && r.snapshotCount > 0;
        const hasVariancePct = r.variancePct != null;
        const variancePctFormatted = hasVariancePct
            ? (r.variancePct >= 0 ? '+' : '') + r.variancePct.toFixed(1)
            : null;
        const varianceClass = hasVariancePct
            ? (r.variancePct >= 0 ? 'positive-variance' : 'negative-variance')
            : '';

        return {
            ...r,
            key:                 `${r.periodYear}-${r.periodMonth}`,
            periodLabel:         `${monthName} ${r.periodYear}`,
            statusBadgeClass,
            hasSnapshots,
            hasPeriodCloseId:    !!r.periodCloseId,
            hasVariancePct,
            variancePctFormatted,
            varianceClass
        };
    }

    _badgeClass(status) {
        if (status === 'Closed')      return 'slds-badge slds-theme_inverse';
        if (status === 'Reopened')    return 'slds-badge slds-theme_warning';
        if (status === 'Open')        return 'slds-badge slds-theme_success';
        return 'slds-badge slds-badge_lightest';
    }

    // ── Drill-down ────────────────────────────────────────────────────────────

    async handleViewDetail(event) {
        const periodCloseId = event.target.dataset.periodCloseId;
        const row = this.rows.find(r => r.periodCloseId === periodCloseId);
        this._drilldownPeriodCloseId = periodCloseId;
        this.drilldownPeriodLabel    = row?.periodLabel || '';
        this.showDrilldown           = true;
        this.isDrilldownLoading      = true;
        this.drilldownRows           = [];

        try {
            const snaps = await getSnapshotsForPeriod({ periodCloseId });
            this.drilldownRows = snaps.map(s => this._enrichSnap(s));
        } catch (e) {
            this._toast(e.body?.message || 'Failed to load snapshots.', 'error');
        } finally {
            this.isDrilldownLoading = false;
        }
    }

    _enrichSnap(s) {
        const hasVariancePct = s.variancePct != null;
        const variancePctFormatted = hasVariancePct
            ? (s.variancePct >= 0 ? '+' : '') + s.variancePct.toFixed(1)
            : null;
        const varianceClass = (s.varianceAmount || 0) >= 0
            ? 'positive-variance'
            : 'negative-variance';
        return {
            ...s,
            hasVariancePct,
            variancePctFormatted,
            varianceClass
        };
    }

    handleCloseDrilldown() {
        this.showDrilldown = false;
        this.drilldownRows = [];
    }

    // ── Computed ──────────────────────────────────────────────────────────────

    get hasDrilldownRows() {
        return this.drilldownRows && this.drilldownRows.length > 0;
    }

    // ── Refresh ───────────────────────────────────────────────────────────────

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this._wiredResult);
    }

    // ── Toast ─────────────────────────────────────────────────────────────────

    _toast(message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
