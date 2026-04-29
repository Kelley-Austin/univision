import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLateActuals from '@salesforce/apex/PeriodCloseController.getLateActuals';
import acceptLateActual from '@salesforce/apex/PeriodCloseController.acceptLateActual';
import rejectLateActual from '@salesforce/apex/PeriodCloseController.rejectLateActual';

const MONTH_OPTIONS = [
    { label: 'All', value: '' },
    { label: 'January',   value: '1'  }, { label: 'February',  value: '2'  },
    { label: 'March',     value: '3'  }, { label: 'April',     value: '4'  },
    { label: 'May',       value: '5'  }, { label: 'June',      value: '6'  },
    { label: 'July',      value: '7'  }, { label: 'August',    value: '8'  },
    { label: 'September', value: '9'  }, { label: 'October',   value: '10' },
    { label: 'November',  value: '11' }, { label: 'December',  value: '12' }
];

export default class LateActualsWorklist extends LightningElement {
    @api periodYear;
    @api periodMonth;

    @track rows         = [];
    @track isLoading    = true;
    @track hasError     = false;
    @track errorMessage = '';
    @track filterYear   = null;
    @track filterMonth  = '';

    monthOptions = MONTH_OPTIONS;

    connectedCallback() {
        if (this.periodYear)  this.filterYear  = this.periodYear;
        if (this.periodMonth) this.filterMonth = String(this.periodMonth);
        this._loadRows();
    }

    get hasRows() { return this.rows && this.rows.length > 0; }

    // ── Filter handlers ────────────────────────────────────────────────────────

    handleYearChange(event) {
        this.filterYear = event.detail.value ? parseInt(event.detail.value, 10) : null;
    }

    handleMonthChange(event) {
        this.filterMonth = event.detail.value;
    }

    handleRefresh() {
        this._loadRows();
    }

    // ── Load worklist ──────────────────────────────────────────────────────────

    async _loadRows() {
        this.isLoading = true;
        this.hasError  = false;
        try {
            const yr = this.filterYear  || null;
            const mo = this.filterMonth ? parseInt(this.filterMonth, 10) : null;
            this.rows = await getLateActuals({ periodYear: yr, periodMonth: mo });
        } catch (e) {
            this.hasError     = true;
            this.errorMessage = e.body?.message || 'Failed to load late actuals';
        } finally {
            this.isLoading = false;
        }
    }

    // ── Accept / Reject ────────────────────────────────────────────────────────

    async handleAccept(event) {
        const id = event.currentTarget.dataset.id;
        await this._updateRow(id, () => acceptLateActual({ actualId: id }), 'Actual accepted.');
    }

    async handleReject(event) {
        const id = event.currentTarget.dataset.id;
        await this._updateRow(id, () => rejectLateActual({ actualId: id }), 'Actual rejected.');
    }

    async _updateRow(id, apexFn, successMsg) {
        this.isLoading = true;
        try {
            await apexFn();
            this.rows = this.rows.filter(r => r.actualId !== id);
            this._toast(successMsg, 'success');
        } catch (e) {
            this._toast(e.body?.message || 'Unexpected error', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Toast helper ──────────────────────────────────────────────────────────

    _toast(message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
