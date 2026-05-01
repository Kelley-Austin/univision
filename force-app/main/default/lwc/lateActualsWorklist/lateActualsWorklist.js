import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLateActuals  from '@salesforce/apex/LateActualsController.getLateActuals';
import acceptLateActual from '@salesforce/apex/LateActualsController.acceptLateActual';
import rejectLateActual from '@salesforce/apex/LateActualsController.rejectLateActual';
import bulkDispose      from '@salesforce/apex/LateActualsController.bulkDispose';

const PAGE_SIZE = 50;

export default class LateActualsWorklist extends LightningElement {

    @track rows = [];
    @track totalCount = 0;
    @track isLoading  = false;
    @track hasError   = false;
    @track errorMessage = '';
    @track currentPage  = 1;

    _selected = new Set();

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this._load();
    }

    // ── Data load ─────────────────────────────────────────────────────────────

    async _load() {
        this.isLoading = true;
        this.hasError  = false;
        try {
            const result = await getLateActuals({
                pageSize:   PAGE_SIZE,
                pageOffset: this.pageOffset
            });
            this.totalCount = result.totalCount;
            this.rows = result.rows.map(r => ({
                ...r,
                isSelected: this._selected.has(r.actualId)
            }));
        } catch (e) {
            this.hasError = true;
            this.errorMessage = e.body?.message || 'Failed to load late actuals.';
            this.rows = [];
            this.totalCount = 0;
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed ──────────────────────────────────────────────────────────────

    get pageOffset()     { return (this.currentPage - 1) * PAGE_SIZE; }
    get hasRows()        { return this.rows && this.rows.length > 0; }
    get isPrevDisabled() { return this.currentPage <= 1; }
    get isNextDisabled() { return this.currentPage * PAGE_SIZE >= this.totalCount; }
    get selectedCount()  { return this._selected.size; }
    get hasSelection()   { return this._selected.size > 0; }
    get allSelected()    { return this.rows.length > 0 && this._selected.size === this.rows.length; }

    // ── Selection ─────────────────────────────────────────────────────────────

    handleSelectAll(event) {
        if (event.target.checked) {
            this.rows.forEach(r => this._selected.add(r.actualId));
        } else {
            this._selected = new Set();
        }
        this._refreshSelectionState();
    }

    handleRowSelect(event) {
        const id = event.target.dataset.actualId;
        event.target.checked ? this._selected.add(id) : this._selected.delete(id);
        this._refreshSelectionState();
    }

    _refreshSelectionState() {
        this.rows = this.rows.map(r => ({ ...r, isSelected: this._selected.has(r.actualId) }));
    }

    // ── Single-row accept / reject ────────────────────────────────────────────

    async handleAccept(event) {
        const actualId = event.target.dataset.actualId;
        this.isLoading = true;
        try {
            await acceptLateActual({ actualId });
            this._toast('Actual accepted', 'success');
            this._selected.delete(actualId);
            await this._load();
        } catch (e) {
            this._toast(e.body?.message || 'Accept failed', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleReject(event) {
        const actualId = event.target.dataset.actualId;
        this.isLoading = true;
        try {
            await rejectLateActual({ actualId });
            this._toast('Actual rejected', 'success');
            this._selected.delete(actualId);
            await this._load();
        } catch (e) {
            this._toast(e.body?.message || 'Reject failed', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Bulk ──────────────────────────────────────────────────────────────────

    async handleBulkAccept() {
        await this._bulkAction('Accepted', 'Accepted');
    }

    async handleBulkReject() {
        await this._bulkAction('Rejected', 'Rejected');
    }

    async _bulkAction(disposition, label) {
        if (!this._selected.size) return;
        const ids = [...this._selected];
        this.isLoading = true;
        try {
            await bulkDispose({ actualIds: ids, disposition });
            this._toast(`${ids.length} actual(s) ${label.toLowerCase()}`, 'success');
            this._selected = new Set();
            await this._load();
        } catch (e) {
            this._toast(e.body?.message || `Bulk ${label.toLowerCase()} failed`, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    handlePrev() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this._selected = new Set();
            this._load();
        }
    }

    handleNext() {
        if (!this.isNextDisabled) {
            this.currentPage++;
            this._selected = new Set();
            this._load();
        }
    }

    handleRefresh() {
        this._selected = new Set();
        this._load();
    }

    // ── Toast ─────────────────────────────────────────────────────────────────

    _toast(message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
