import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getPeriodSummary from '@salesforce/apex/PeriodCloseController.getPeriodSummary';
import closePeriodAsync from '@salesforce/apex/PeriodCloseController.closePeriodAsync';
import reopenPeriod    from '@salesforce/apex/PeriodCloseController.reopenPeriod';

const MONTH_NAMES = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
];

export default class PeriodCloseActions extends NavigationMixin(LightningElement) {
    @api recordId;

    @track summary = {};
    @track isLoading = true;
    @track hasError  = false;
    @track errorMessage = '';
    @track showCloseModal  = false;
    @track showReopenModal = false;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this._loadSummary();
    }

    // ── Data load ─────────────────────────────────────────────────────────────

    async _loadSummary() {
        this.isLoading = true;
        this.hasError  = false;
        try {
            this.summary = await getPeriodSummary({ periodCloseId: this.recordId });
        } catch (e) {
            this.hasError = true;
            this.errorMessage = e.body?.message || 'Failed to load period summary.';
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed properties ───────────────────────────────────────────────────

    get periodLabel() {
        if (!this.summary?.periodYear) return '';
        const month = MONTH_NAMES[this.summary.periodMonth] || this.summary.periodMonth;
        return `${month} ${this.summary.periodYear}`;
    }

    get statusBadgeClass() {
        const s = this.summary?.status;
        if (s === 'Closed')   return 'slds-badge slds-theme_inverse';
        if (s === 'Reopened') return 'slds-badge slds-theme_warning';
        return 'slds-badge slds-theme_success';
    }

    get canClose() {
        const s = this.summary?.status;
        return s === 'Open' || s === 'Reopened';
    }

    get canReopen() {
        return this.summary?.status === 'Closed';
    }

    get showActualsWarning() {
        return (this.summary?.projectionsWithoutActuals || 0) > 0;
    }

    get reopenedBefore() {
        return (this.summary?.reopenCount || 0) > 0;
    }

    // ── Close flow ────────────────────────────────────────────────────────────

    handleCloseClick() {
        this.showCloseModal = true;
    }

    handleCancelClose() {
        this.showCloseModal = false;
    }

    async handleConfirmClose() {
        this.showCloseModal = false;
        this.isLoading = true;
        try {
            const result = await closePeriodAsync({ periodCloseId: this.recordId });
            const isAsync = result.startsWith('async:');
            const msg = isAsync
                ? 'Period close queued. Snapshots will be generated shortly.'
                : `Period closed. ${result.split(':')[1]} snapshot(s) created.`;
            this._toast(msg, 'success');
            await this._loadSummary();
        } catch (e) {
            this._toast(e.body?.message || 'Close failed.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Reopen flow ───────────────────────────────────────────────────────────

    handleReopenClick() {
        this.showReopenModal = true;
    }

    handleCancelReopen() {
        this.showReopenModal = false;
    }

    async handleConfirmReopen() {
        this.showReopenModal = false;
        this.isLoading = true;
        try {
            await reopenPeriod({ periodCloseId: this.recordId });
            this._toast('Period reopened.', 'success');
            await this._loadSummary();
        } catch (e) {
            this._toast(e.body?.message || 'Reopen failed.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Toast ─────────────────────────────────────────────────────────────────

    _toast(message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
