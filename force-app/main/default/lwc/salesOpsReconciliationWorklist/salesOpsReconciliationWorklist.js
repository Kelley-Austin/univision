import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getSalesOpsWorklist from '@salesforce/apex/ReconciliationController.getSalesOpsWorklist';
import acceptMatch from '@salesforce/apex/ReconciliationController.acceptMatch';
import excludeRow from '@salesforce/apex/ReconciliationController.excludeRow';

// Batch invocable via Apex anonymous / Screen Flow
import runReconciliationBatch from '@salesforce/apex/ReconciliationController.runReconciliationBatch';

const PAGE_SIZE = 100;

export default class SalesOpsReconciliationWorklist extends LightningElement {

    @track rows = [];
    @track totalCount = 0;
    @track isLoading = false;
    @track hasError = false;
    @track errorMessage = '';
    @track currentPage = 1;

    // Filters
    @track filterAeUserId = null;
    @track filterSourceSystem = null;
    @track filterMonth = null;
    @track filterYear = null;

    // Committed filter values (applied on "Apply Filters")
    _activeAeUserId = null;
    _activeSourceSystem = null;
    _activeMonth = null;
    _activeYear = null;

    // Selection state
    @track _selected = new Set();

    // Static filter options (AEs / source systems loaded lazily in a real org)
    @track aeOptions = [{ label: 'All AEs', value: '' }];
    @track sourceSystemOptions = [
        { label: 'All Sources', value: '' },
        { label: 'WideOrbit', value: 'WIDEORBIT' },
        { label: 'Counterpoint', value: 'COUNTERPOINT' },
        { label: 'Strata', value: 'STRATA' },
        { label: 'CoxReps', value: 'COXREPS' },
        { label: 'Operative', value: 'OPERATIVE' }
    ];

    _wiredResult;

    // ── Wire ──────────────────────────────────────────────────────────────────

    @wire(getSalesOpsWorklist, {
        filterAeUserId:     '$_activeAeUserId',
        filterSourceSystem: '$_activeSourceSystem',
        filterMonth:        '$_activeMonth',
        filterYear:         '$_activeYear',
        pageSize:           PAGE_SIZE,
        pageOffset:         '$pageOffset'
    })
    wiredWorklist(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error.body?.message || 'Failed to load worklist';
            this.rows = [];
            this.totalCount = 0;
        } else if (result.data) {
            this.hasError = false;
            this.totalCount = result.data.totalCount;
            this.rows = result.data.rows.map(r => this._enrichRow(r));
        }
    }

    // ── Computed ──────────────────────────────────────────────────────────────

    get pageOffset() {
        return (this.currentPage - 1) * PAGE_SIZE;
    }

    get hasRows() {
        return this.rows && this.rows.length > 0;
    }

    get isPrevDisabled() {
        return this.currentPage <= 1;
    }

    get isNextDisabled() {
        return this.currentPage * PAGE_SIZE >= this.totalCount;
    }

    get selectedCount() {
        return this._selected.size;
    }

    get hasSelection() {
        return this._selected.size > 0;
    }

    get allSelected() {
        return this.rows.length > 0 && this._selected.size === this.rows.length;
    }

    // ── Row enrichment ────────────────────────────────────────────────────────

    _enrichRow(r) {
        const tier = r.matchAccountTier;
        const tierBadgeClass = tier === 1
            ? 'slds-badge slds-theme_success'
            : tier === 2
            ? 'slds-badge slds-theme_warning'
            : 'slds-badge slds-theme_error';

        return {
            ...r,
            topSuggestion: r.suggestions && r.suggestions.length > 0 ? r.suggestions[0] : null,
            tierBadgeClass,
            isSelected: this._selected.has(r.stagingId)
        };
    }

    // ── Filter handlers ───────────────────────────────────────────────────────

    handleFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this[field] = value || null;
    }

    handleApplyFilters() {
        this._activeAeUserId     = this.filterAeUserId     || null;
        this._activeSourceSystem = this.filterSourceSystem || null;
        this._activeMonth        = this.filterMonth        ? parseInt(this.filterMonth, 10) : null;
        this._activeYear         = this.filterYear         ? parseInt(this.filterYear,  10) : null;
        this.currentPage = 1;
        this._selected = new Set();
    }

    handleClearFilters() {
        this.filterAeUserId = null;
        this.filterSourceSystem = null;
        this.filterMonth = null;
        this.filterYear = null;
        this.handleApplyFilters();
    }

    // ── Selection handlers ────────────────────────────────────────────────────

    handleSelectAll(event) {
        if (event.target.checked) {
            this.rows.forEach(r => this._selected.add(r.stagingId));
        } else {
            this._selected = new Set();
        }
        this.rows = this.rows.map(r => ({ ...r, isSelected: this._selected.has(r.stagingId) }));
    }

    handleRowSelect(event) {
        const stagingId = event.target.dataset.stagingId;
        if (event.target.checked) {
            this._selected.add(stagingId);
        } else {
            this._selected.delete(stagingId);
        }
        this.rows = this.rows.map(r =>
            r.stagingId === stagingId ? { ...r, isSelected: event.target.checked } : r
        );
    }

    // ── Accept ────────────────────────────────────────────────────────────────

    async handleAccept(event) {
        const stagingId = event.target.dataset.stagingId;
        const accountId = event.target.dataset.accountId;
        const tier = parseInt(event.target.dataset.tier, 10) || 2;
        this.isLoading = true;
        try {
            const outcome = await acceptMatch({ stagingId, accountId, tier });
            if (outcome === 'success') {
                this._toast('Row matched', 'success');
                await refreshApex(this._wiredResult);
            } else {
                this._toast(outcome, 'error');
            }
        } catch (e) {
            this._toast(e.body?.message || 'Unexpected error', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Exclude ───────────────────────────────────────────────────────────────

    async handleExclude(event) {
        const stagingId = event.target.dataset.stagingId;
        await this._doExclude(stagingId, 'SALES_OPS_EXCLUDE');
    }

    async handleBulkExclude() {
        if (!this._selected.size) return;
        this.isLoading = true;
        try {
            for (const stagingId of this._selected) {
                await excludeRow({ stagingId, reason: 'BULK_EXCLUDE' });
            }
            this._selected = new Set();
            this._toast(`${this.selectedCount} rows excluded`, 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this._toast(e.body?.message || 'Bulk exclude failed', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async _doExclude(stagingId, reason) {
        this.isLoading = true;
        try {
            const outcome = await excludeRow({ stagingId, reason });
            if (outcome === 'success') {
                this._toast('Row excluded', 'success');
                await refreshApex(this._wiredResult);
            } else {
                this._toast(outcome, 'error');
            }
        } catch (e) {
            this._toast(e.body?.message || 'Unexpected error', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Run reconciliation batch ──────────────────────────────────────────────

    async handleRunBatch() {
        this.isLoading = true;
        try {
            if (typeof runReconciliationBatch === 'function') {
                await runReconciliationBatch({});
                this._toast('Reconciliation batch queued', 'success');
            } else {
                this._toast('Batch launch not wired — run from Setup → Apex', 'info');
            }
        } catch (e) {
            this._toast(e.body?.message || 'Could not queue batch', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    handlePrev() {
        if (this.currentPage > 1) { this.currentPage--; this._selected = new Set(); }
    }

    handleNext() {
        if (!this.isNextDisabled) { this.currentPage++; this._selected = new Set(); }
    }

    handleRefresh() {
        this.isLoading = true;
        this._selected = new Set();
        refreshApex(this._wiredResult);
    }

    // ── Toast ─────────────────────────────────────────────────────────────────

    _toast(message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
