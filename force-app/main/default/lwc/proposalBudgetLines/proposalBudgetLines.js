import { LightningElement, api, wire, track } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getActiveChannels from '@salesforce/apex/CreateLocalAdProposal.getActiveChannels';
import getActiveVehicles from '@salesforce/apex/CreateLocalAdProposal.getActiveVehicles';

const MONTHS = [
    { label: 'January',   value: 'January'   },
    { label: 'February',  value: 'February'  },
    { label: 'March',     value: 'March'     },
    { label: 'April',     value: 'April'     },
    { label: 'May',       value: 'May'       },
    { label: 'June',      value: 'June'      },
    { label: 'July',      value: 'July'      },
    { label: 'August',    value: 'August'    },
    { label: 'September', value: 'September' },
    { label: 'October',   value: 'October'   },
    { label: 'November',  value: 'November'  },
    { label: 'December',  value: 'December'  }
];

let _rowIdCounter = 0;

export default class ProposalBudgetLines extends LightningElement {
    // Flow output properties
    @api selectedVehicleId = '';
    @api budgetLinesJson   = '[]';

    @track rows           = [this._newRow()];
    @track channelOptions = [];
    @track vehicleOptions = [];
    @track selectedVehicle = null;
    @track hasError        = false;
    @track validationError = '';

    _vehicleMap = {};

    @wire(getActiveChannels)
    wiredChannels({ data }) {
        if (data) {
            this.channelOptions = data.map(ch => ({
                label: ch.Name,
                value: ch.Id
            }));
        }
    }

    @wire(getActiveVehicles)
    wiredVehicles({ data }) {
        if (data) {
            this.vehicleOptions = data.map(v => ({ label: v.Name, value: v.Id }));
            this._vehicleMap = data.reduce((acc, v) => {
                acc[v.Id] = v;
                return acc;
            }, {});
        }
    }

    get monthOptions() {
        return MONTHS;
    }

    get isOnlyRow() {
        return this.rows.length === 1;
    }

    get rateCardFormatted() {
        const rc = this.selectedVehicle?.Rate_Card__c;
        if (rc == null) return '—';
        return new Intl.NumberFormat('en-US', {
            style: 'currency', currency: 'USD'
        }).format(rc);
    }

    handleVehicleChange(event) {
        const vehicleId = event.detail.value;
        this.selectedVehicleId = vehicleId;
        this.selectedVehicle   = this._vehicleMap[vehicleId] || null;
        this.dispatchEvent(
            new FlowAttributeChangeEvent('selectedVehicleId', vehicleId)
        );
        this._publishBudgetLines();
    }

    handleAddRow() {
        this.rows = [...this.rows, this._newRow()];
        this._publishBudgetLines();
    }

    handleRemoveRow(event) {
        const rowId = event.currentTarget.dataset.rowId;
        if (this.rows.length > 1) {
            this.rows = this.rows.filter(r => r.id !== rowId);
            this._publishBudgetLines();
        }
    }

    handleFieldChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;
        this.rows = this.rows.map(r =>
            r.id === rowId ? { ...r, [field]: value } : r
        );
        this._publishBudgetLines();
    }

    @api
    validate() {
        this.hasError = false;
        this.validationError = '';

        if (!this.selectedVehicleId) {
            this.hasError      = true;
            this.validationError = 'Please select a vehicle before continuing.';
            return { isValid: false, errorMessage: this.validationError };
        }

        const allRowsValid = this.rows.every(r =>
            r.channelId &&
            r.month &&
            r.fiscalYear &&
            r.plannedAmount > 0
        );

        if (!allRowsValid) {
            this.hasError        = true;
            this.validationError = 'Each budget line must have a channel, month, fiscal year, and planned amount greater than zero.';
            return { isValid: false, errorMessage: this.validationError };
        }

        return { isValid: true, errorMessage: '' };
    }

    _newRow() {
        return {
            id:            String(_rowIdCounter++),
            channelId:     '',
            month:         '',
            fiscalYear:    String(new Date().getFullYear()),
            plannedAmount: null,
            notes:         ''
        };
    }

    _publishBudgetLines() {
        const json = JSON.stringify(
            this.rows.map(r => ({
                channelId:     r.channelId,
                month:         r.month,
                fiscalYear:    r.fiscalYear,
                plannedAmount: r.plannedAmount,
                notes:         r.notes
            }))
        );
        this.budgetLinesJson = json;
        this.dispatchEvent(
            new FlowAttributeChangeEvent('budgetLinesJson', json)
        );
    }
}
