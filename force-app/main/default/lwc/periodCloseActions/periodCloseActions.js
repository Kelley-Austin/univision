import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue, refreshApex } from 'lightning/uiRecordApi';
import getProjectionsWithoutActuals from '@salesforce/apex/PeriodCloseController.getProjectionsWithoutActuals';
import closePeriod from '@salesforce/apex/PeriodCloseController.closePeriod';
import reopenPeriod from '@salesforce/apex/PeriodCloseController.reopenPeriod';

import STATUS_FIELD from '@salesforce/schema/Period_Close__c.Status__c';

const FIELDS = [STATUS_FIELD];

export default class PeriodCloseActions extends LightningElement {
    @api recordId;

    @track isLoading     = false;
    @track hasError      = false;
    @track errorMessage  = '';
    @track warnings      = [];
    @track showModal     = false;
    @track pendingAction = null; // 'close' | 'reopen'

    _wiredRecord;
    _recordStatus = '';

    // ── Wire: current record status ───────────────────────────────────────────

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord(result) {
        this._wiredRecord = result;
        if (result.data) {
            this._recordStatus = getFieldValue(result.data, STATUS_FIELD) || '';
            this.hasError = false;
        } else if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error.body?.message || 'Failed to load record';
        }
    }

    // ── Computed ──────────────────────────────────────────────────────────────

    get recordStatus() { return this._recordStatus; }

    get canClose()   { return this._recordStatus === 'Open' || this._recordStatus === 'Reopened'; }
    get canReopen()  { return this._recordStatus === 'Closed'; }
    get hasActions() { return this.canClose || this.canReopen; }

    get hasWarnings()  { return this.warnings && this.warnings.length > 0; }
    get warningCount() { return this.warnings ? this.warnings.length : 0; }

    get statusBadgeClass() {
        const base = 'slds-badge ';
        if (this._recordStatus === 'Closed')   return base + 'slds-badge_lightest';
        if (this._recordStatus === 'Reopened') return base + 'slds-theme_warning';
        return base + 'slds-badge_inverse';
    }

    get modalTitle() {
        return this.pendingAction === 'close' ? 'Confirm: Close Period' : 'Confirm: Reopen Period';
    }
    get modalBody() {
        return this.pendingAction === 'close'
            ? 'Closing this period will snapshot all Projections with their current Actual amounts. This action can be undone by reopening the period.'
            : 'Reopening this period will allow new actuals to be entered. Existing snapshots will be updated when you re-close.';
    }
    get modalConfirmLabel() {
        return this.pendingAction === 'close' ? 'Close Period' : 'Reopen Period';
    }

    // ── Close button clicked ───────────────────────────────────────────────────

    async handleCloseClick() {
        this.isLoading = true;
        this.warnings  = [];
        this.hasError  = false;
        try {
            this.warnings = await getProjectionsWithoutActuals({ periodCloseId: this.recordId });
        } catch (e) {
            // Non-fatal: show modal anyway, warning load failure doesn't block close
        } finally {
            this.isLoading = false;
        }
        this.pendingAction = 'close';
        this.showModal = true;
    }

    // ── Reopen button clicked ──────────────────────────────────────────────────

    handleReopenClick() {
        this.pendingAction = 'reopen';
        this.showModal = true;
    }

    handleCancelModal() {
        this.showModal = false;
        this.pendingAction = null;
    }

    // ── Confirmed action ───────────────────────────────────────────────────────

    async handleConfirm() {
        this.showModal = false;
        this.isLoading = true;
        this.hasError  = false;
        try {
            let result;
            if (this.pendingAction === 'close') {
                result = await closePeriod({ periodCloseId: this.recordId });
            } else {
                result = await reopenPeriod({ periodCloseId: this.recordId });
            }

            if (result.success) {
                this._toast(result.message, 'success');
                this.warnings = [];
                await refreshApex(this._wiredRecord);
            } else {
                this.hasError     = true;
                this.errorMessage = result.message;
            }
        } catch (e) {
            this.hasError     = true;
            this.errorMessage = e.body?.message || 'Unexpected error';
        } finally {
            this.isLoading     = false;
            this.pendingAction = null;
        }
    }

    // ── Toast helper ──────────────────────────────────────────────────────────

    _toast(message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
