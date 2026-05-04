import { LightningElement, api, wire, track } from 'lwc';
import getActiveChannels from '@salesforce/apex/CreateOpportunityWithBudgetLines.getActiveChannels';

const MONTH_OPTIONS = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
].map(m => ({ label: m, value: m }));

let _idCounter = 0;

export default class BudgetLineEditor extends LightningElement {
    @api budgetLinesJson = '[]';

    @track _lines = [];
    @track error;

    channelOptions = [];

    get monthOptions() {
        return MONTH_OPTIONS;
    }

    get lines() {
        return this._lines;
    }

    get hasLines() {
        return this._lines.length > 0;
    }

    get totalFormatted() {
        const total = this._lines.reduce((sum, l) => sum + (parseFloat(l.plannedAmount) || 0), 0);
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(total);
    }

    connectedCallback() {
        try {
            const existing = JSON.parse(this.budgetLinesJson || '[]');
            this._lines = existing.map(l => ({ ...l, _id: _idCounter++ }));
        } catch (e) {
            this._lines = [];
        }
    }

    @wire(getActiveChannels)
    handleChannels({ data, error }) {
        if (data) {
            this.channelOptions = data.map(c => ({
                label: c.Channel_Type__c ? `${c.Name} (${c.Channel_Type__c})` : c.Name,
                value: c.Id
            }));
            this.error = null;
        } else if (error) {
            this.error = 'Could not load channels. Refresh the page or contact your administrator.';
        }
    }

    handleAddLine() {
        this._lines = [
            ...this._lines,
            { _id: _idCounter++, channelId: '', month: '', fiscalYear: '', plannedAmount: null, notes: '' }
        ];
        this._syncOutput();
    }

    handleRemoveLine(event) {
        const rowId = parseInt(event.currentTarget.dataset.rowId, 10);
        this._lines = this._lines.filter(l => l._id !== rowId);
        this._syncOutput();
    }

    handleFieldChange(event) {
        const rowId = parseInt(event.currentTarget.dataset.rowId, 10);
        const field = event.currentTarget.dataset.field;
        const raw   = event.detail.value;
        const value = field === 'plannedAmount' ? (parseFloat(raw) || 0) : raw;
        this._lines = this._lines.map(l => l._id === rowId ? { ...l, [field]: value } : l);
        this._syncOutput();
    }

    _syncOutput() {
        this.budgetLinesJson = JSON.stringify(
            this._lines.map(({ channelId, month, fiscalYear, plannedAmount, notes }) => ({
                channelId,
                month,
                fiscalYear,
                plannedAmount: plannedAmount || 0,
                notes: notes || ''
            }))
        );
    }

    @api
    validate() {
        if (this._lines.length === 0) {
            return { isValid: false, errorMessage: 'Add at least one budget line before saving.' };
        }

        const invalid = this._lines.filter(
            l => !l.channelId || !l.month || !l.fiscalYear || !(l.plannedAmount > 0)
        );

        if (invalid.length > 0) {
            return {
                isValid: false,
                errorMessage: `${invalid.length} line(s) are missing required fields. Check Channel, Month, Fiscal Year, and Planned Amount.`
            };
        }

        return { isValid: true };
    }
}
