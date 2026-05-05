import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getAeWorklist from '@salesforce/apex/ReconciliationController.getAeWorklist';
import acceptMatch from '@salesforce/apex/ReconciliationController.acceptMatch';
import excludeRow from '@salesforce/apex/ReconciliationController.excludeRow';
import searchAccounts from '@salesforce/apex/ReconciliationController.searchAccounts';

const PAGE_SIZE = 50;

export default class AeReconciliationWorklist extends LightningElement {
    @api aeUserId;

    @track rows = [];
    @track totalCount = 0;
    @track isLoading = false;
    @track hasError = false;
    @track errorMessage = '';
    @track currentPage = 1;

    // Search modal state
    @track showSearchModal = false;
    @track searchTerm = '';
    @track searchResults = [];
    activeStagingId = null;

    // Row-level selection state (stagingId → {accountId, tier})
    _rowSelections = {};

    _wiredResult;

    // ── Wire: load worklist ───────────────────────────────────────────────────

    @wire(getAeWorklist, {
        aeUserId: '$aeUserId',
        pageSize: PAGE_SIZE,
        pageOffset: '$pageOffset'
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

    // ── Computed properties ───────────────────────────────────────────────────

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

    // ── Enrichment: add computed fields to each row ───────────────────────────

    _enrichRow(r) {
        const sel = this._rowSelections[r.stagingId] || {};
        const suggestionOptions = (r.suggestions || []).map(s => ({
            label: `${s.accountName} (${s.score}%)`,
            value: s.accountId
        }));
        return {
            ...r,
            hasSuggestions: suggestionOptions.length > 0,
            suggestionOptions,
            selectedAccountId: sel.accountId || (suggestionOptions[0]?.value ?? null),
            selectedTier: sel.tier || 2,
            noSelection: !sel.accountId && suggestionOptions.length === 0
        };
    }

    // ── Suggestion combobox selection ─────────────────────────────────────────

    handleSuggestionSelect(event) {
        const stagingId = event.target.dataset.stagingId;
        const accountId = event.detail.value;
        this._rowSelections[stagingId] = { accountId, tier: 2 };
        this.rows = this.rows.map(r =>
            r.stagingId === stagingId
                ? { ...r, selectedAccountId: accountId, noSelection: false }
                : r
        );
    }

    // ── Accept match ──────────────────────────────────────────────────────────

    async handleAccept(event) {
        const stagingId = event.target.dataset.stagingId;
        const accountId = event.target.dataset.accountId;
        const tier = parseInt(event.target.dataset.tier, 10) || 2;
        if (!accountId) { this._toast('No account selected', 'error'); return; }

        this.isLoading = true;
        try {
            const outcome = await acceptMatch({ stagingId, accountId, tier });
            if (outcome === 'success') {
                this._toast('Row matched successfully', 'success');
                delete this._rowSelections[stagingId];
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

    // ── Exclude row ───────────────────────────────────────────────────────────

    async handleExclude(event) {
        const stagingId = event.target.dataset.stagingId;
        this.isLoading = true;
        try {
            const outcome = await excludeRow({ stagingId, reason: 'AE_MANUAL_EXCLUDE' });
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

    // ── Manual search modal ───────────────────────────────────────────────────

    handleOpenSearch(event) {
        this.activeStagingId = event.target.dataset.stagingId;
        this.searchTerm = '';
        this.searchResults = [];
        this.showSearchModal = true;
    }

    handleCloseSearch() {
        this.showSearchModal = false;
        this.activeStagingId = null;
    }

    handleSearchTermChange(event) {
        this.searchTerm = event.detail.value;
    }

    async handleSearch() {
        if (!this.searchTerm || this.searchTerm.length < 2) return;
        try {
            this.searchResults = await searchAccounts({ term: this.searchTerm });
        } catch (e) {
            this._toast('Search failed: ' + (e.body?.message || e.message), 'error');
        }
    }

    handleSearchSelect(event) {
        const accountId = event.target.dataset.accountId;
        const label = event.target.label;
        if (this.activeStagingId) {
            this._rowSelections[this.activeStagingId] = { accountId, tier: 3 };
            this.rows = this.rows.map(r =>
                r.stagingId === this.activeStagingId
                    ? { ...r, selectedAccountId: accountId, noSelection: false,
                        selectedTier: 3,
                        suggestionOptions: [{ label, value: accountId }],
                        hasSuggestions: true }
                    : r
            );
        }
        this.showSearchModal = false;
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    handlePrev() {
        if (this.currentPage > 1) this.currentPage--;
    }

    handleNext() {
        if (!this.isNextDisabled) this.currentPage++;
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this._wiredResult);
    }

    // ── Toast helper ──────────────────────────────────────────────────────────

    _toast(message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
