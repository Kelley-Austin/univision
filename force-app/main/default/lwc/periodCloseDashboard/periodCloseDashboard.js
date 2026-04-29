import { LightningElement, track, wire } from 'lwc';
import getDashboardData from '@salesforce/apex/PeriodCloseController.getDashboardData';
import getPeriodSnapshots from '@salesforce/apex/PeriodCloseController.getPeriodSnapshots';

export default class PeriodCloseDashboard extends LightningElement {
    @track rows         = [];
    @track isLoading    = true;
    @track hasError     = false;
    @track errorMessage = '';

    // key → expanded snapshot rows
    _expandedKeys = new Set();
    _snapshotCache = {};

    // ── Wire: dashboard summary ────────────────────────────────────────────────

    @wire(getDashboardData)
    wiredDashboard({ data, error }) {
        this.isLoading = false;
        if (error) {
            this.hasError     = true;
            this.errorMessage = error.body?.message || 'Failed to load dashboard';
        } else if (data) {
            this.hasError = false;
            this.rows = data.map(r => this._enrichRow(r));
        }
    }

    // ── Row enrichment ─────────────────────────────────────────────────────────

    _enrichRow(r) {
        const isExpanded = this._expandedKeys.has(r.periodLabel);
        const snapshots  = isExpanded
            ? (this._snapshotCache[r.periodCloseId] || []).map(s => this._enrichSnap(s))
            : [];
        return {
            ...r,
            hasData:       r.projected != null || r.actual != null,
            hasDrilldown:  r.periodCloseId != null && r.status !== 'No Record',
            hasVariance:   r.variancePct != null,
            variancePctFormatted: r.variancePct != null
                ? r.variancePct.toFixed(1)
                : null,
            varianceClass: this._varianceClass(r.variancePct),
            statusBadgeClass: this._statusClass(r.status),
            isExpanded,
            snapshots
        };
    }

    _enrichSnap(s) {
        return {
            ...s,
            hasVariance: s.variancePct != null,
            variancePctFormatted: s.variancePct != null ? s.variancePct.toFixed(1) : null,
            varianceClass: this._varianceClass(s.variancePct)
        };
    }

    _varianceClass(pct) {
        if (pct == null) return '';
        return pct >= 0 ? 'slds-text-color_success' : 'slds-text-color_error';
    }

    _statusClass(status) {
        const base = 'slds-badge ';
        if (status === 'Closed')   return base + 'slds-badge_lightest';
        if (status === 'Reopened') return base + 'slds-theme_warning';
        if (status === 'Open')     return base + 'slds-badge_inverse';
        return base;
    }

    // ── Drilldown: expand / collapse ───────────────────────────────────────────

    async handleDrilldown(event) {
        const pcId = event.currentTarget.dataset.id;
        const row  = this.rows.find(r => r.periodCloseId === pcId);
        if (!row) return;

        const key = row.periodLabel;
        if (this._expandedKeys.has(key)) {
            this._expandedKeys.delete(key);
            this.rows = this.rows.map(r =>
                r.periodLabel === key ? { ...r, isExpanded: false, snapshots: [] } : r
            );
            return;
        }

        // Load snapshots (cached after first fetch)
        if (!this._snapshotCache[pcId]) {
            this.isLoading = true;
            try {
                const snaps = await getPeriodSnapshots({ periodCloseId: pcId });
                this._snapshotCache[pcId] = snaps;
            } catch (e) {
                this.isLoading = false;
                return;
            }
            this.isLoading = false;
        }

        this._expandedKeys.add(key);
        this.rows = this.rows.map(r =>
            r.periodLabel === key
                ? {
                    ...r,
                    isExpanded: true,
                    snapshots: (this._snapshotCache[pcId] || []).map(s => this._enrichSnap(s))
                  }
                : r
        );
    }
}
