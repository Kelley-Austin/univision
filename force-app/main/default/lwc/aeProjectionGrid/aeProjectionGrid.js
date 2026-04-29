import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProjections from '@salesforce/apex/ProjectionService.getProjections';
import upsertProjections from '@salesforce/apex/ProjectionService.upsertProjections';
import checkLock from '@salesforce/apex/BudgetLockService.checkLock';
import getActiveCategories from '@salesforce/apex/CategoryService.getActiveCategories';

const MONTH_LABELS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const REVENUE_TYPE_OPTIONS = [
    { label: 'National TV',  value: 'National TV'  },
    { label: 'Local TV',     value: 'Local TV'      },
    { label: 'Digital',      value: 'Digital'       },
    { label: 'Radio',        value: 'Radio'         },
    { label: 'Streaming',    value: 'Streaming'     },
    { label: 'Other',        value: 'Other'         }
];
const STAGE_OPTIONS = [
    { label: 'Working',   value: 'Working'   },
    { label: 'Pitched',   value: 'Pitched'   },
    { label: 'Committed', value: 'Committed' },
    { label: 'Won',       value: 'Won'       }
];

export default class AeProjectionGrid extends LightningElement {
    @api accountId;

    @track categoryId   = '';
    @track revenueType  = 'National TV';
    @track periodYear   = new Date().getFullYear();
    @track defaultStage = 'Working';
    @track rows         = this._buildEmptyRows();
    @track lockResult   = { isLocked: false, lockMessage: '' };
    @track categoryOptions = [];
    @track isSaving    = false;
    @track errorMessage  = '';
    @track successMessage = '';

    _wireProjectionsResult;
    _wireLockResult;
    _isDirty = false;

    // ── Picklist options ──────────────────────────────────────────────────────

    get revenueTypeOptions() { return REVENUE_TYPE_OPTIONS; }
    get stageOptions()       { return STAGE_OPTIONS; }

    // ── Computed states ───────────────────────────────────────────────────────

    get isLocked()      { return this.lockResult && this.lockResult.isLocked; }
    get isSaveDisabled(){ return this.isLocked || this.isSaving || !this.accountId || !this.categoryId; }

    get formattedTotal() {
        const total = this.rows.reduce((sum, r) => sum + (parseFloat(r.amount) || 0), 0);
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(total);
    }

    // ── Wires ─────────────────────────────────────────────────────────────────

    @wire(getActiveCategories)
    wiredCategories({ error, data }) {
        if (data) {
            this.categoryOptions = data.map(c => ({ label: c.Name, value: c.Id }));
            if (this.categoryOptions.length > 0 && !this.categoryId) {
                this.categoryId = this.categoryOptions[0].value;
            }
        } else if (error) {
            console.error('Failed to load categories', error);
        }
    }

    @wire(getProjections, {
        accountId:   '$accountId',
        categoryId:  '$categoryId',
        revenueType: '$revenueType',
        periodYear:  '$periodYear'
    })
    wiredProjections(result) {
        this._wireProjectionsResult = result;
        const { error, data } = result;
        if (data) {
            this.rows = data.map(r => ({
                month:      r.month,
                monthLabel: r.monthLabel,
                amount:     r.amount || 0,
                stage:      r.stage  || 'Working',
                projId:     r.projId || null
            }));
            this._isDirty = false;
        } else if (error) {
            this.errorMessage = 'Failed to load projections: ' + this._extractError(error);
        }
    }

    @wire(checkLock, {
        accountId:  '$accountId',
        categoryId: '$categoryId',
        revenueType:'$revenueType',
        periodYear: '$periodYear'
    })
    wiredLock(result) {
        this._wireLockResult = result;
        const { error, data } = result;
        if (data) {
            this.lockResult = data;
        } else if (error) {
            // Non-fatal — assume unlocked on error so AE can still work
            this.lockResult = { isLocked: false, lockMessage: '' };
        }
    }

    // ── Event handlers ────────────────────────────────────────────────────────

    handleCategoryChange(event)   { this.categoryId  = event.detail.value; this._clearMessages(); }
    handleRevenueTypeChange(event){ this.revenueType  = event.detail.value; this._clearMessages(); }
    handleYearChange(event)       { this.periodYear   = parseInt(event.detail.value, 10); this._clearMessages(); }
    handleStageChange(event)      { this.defaultStage = event.detail.value; }

    handleAmountChange(event) {
        const month = parseInt(event.target.dataset.month, 10);
        const value = parseFloat(event.target.value) || 0;
        this.rows = this.rows.map(r =>
            r.month === month ? { ...r, amount: value, stage: this.defaultStage } : r
        );
        this._isDirty = true;
        this._clearMessages();
    }

    /**
     * Paste handler: parses tab-separated values from Excel.
     * Expects up to 12 numeric values separated by tabs (one row).
     * If the user pasted multiple rows, each row maps to a sequence starting
     * from the focused cell's month.
     */
    handlePaste(event) {
        event.preventDefault();
        const text = (event.clipboardData || window.clipboardData).getData('text');
        const values = text.replace(/\r\n?/g, '\n').trim().split('\t').map(v => parseFloat(v.replace(/[$, ]/g, '')) || 0);

        // Determine start month: use the focused input if present, else Jan
        const focused = this.template.querySelector('input:focus');
        const startMonth = focused ? parseInt(focused.dataset.month, 10) : 1;
        const startIdx   = startMonth - 1;

        const updated = [...this.rows];
        for (let i = 0; i < values.length && (startIdx + i) < 12; i++) {
            updated[startIdx + i] = { ...updated[startIdx + i], amount: values[i], stage: this.defaultStage };
        }
        this.rows    = updated;
        this._isDirty = true;
        this._clearMessages();
    }

    async handleSave() {
        if (this.isSaveDisabled) { return; }
        this.isSaving = true;
        this._clearMessages();

        const inputs = this.rows.map(r => ({
            accountId:   this.accountId,
            categoryId:  this.categoryId,
            revenueType: this.revenueType,
            periodYear:  this.periodYear,
            periodMonth: r.month,
            amount:      r.amount,
            stage:       r.stage || this.defaultStage
        }));

        try {
            const result = await upsertProjections({ projectionsJson: JSON.stringify(inputs) });
            if (result.success) {
                this.successMessage = result.message;
                this._isDirty = false;
                await refreshApex(this._wireProjectionsResult);
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Saved', message: result.message, variant: 'success'
                }));
            } else {
                this.errorMessage = result.message;
            }
        } catch (err) {
            this.errorMessage = 'Save failed: ' + this._extractError(err);
        } finally {
            this.isSaving = false;
        }
    }

    handleReset() {
        this._isDirty = false;
        this._clearMessages();
        refreshApex(this._wireProjectionsResult);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _buildEmptyRows() {
        return MONTH_LABELS.map((label, idx) => ({
            month:      idx + 1,
            monthLabel: label,
            amount:     0,
            stage:      'Working',
            projId:     null
        }));
    }

    _clearMessages() {
        this.errorMessage   = '';
        this.successMessage = '';
    }

    _extractError(err) {
        if (typeof err === 'string') { return err; }
        if (err?.body?.message)     { return err.body.message; }
        if (err?.message)           { return err.message; }
        return JSON.stringify(err);
    }
}
