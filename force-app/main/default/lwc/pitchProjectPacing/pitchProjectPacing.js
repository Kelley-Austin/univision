import { LightningElement, api, wire, track } from 'lwc';
import getPacingData from '@salesforce/apex/PitchProjectController.getPacingData';

const USD_FMT = new Intl.NumberFormat('en-US', {
    style              : 'currency',
    currency           : 'USD',
    maximumFractionDigits: 0
});

export default class PitchProjectPacing extends LightningElement {

    @api recordId;

    @track _data      = null;
    @track _error     = null;
    @track isLoading  = true;

    // ── Wire ─────────────────────────────────────────────────────────────

    @wire(getPacingData, { projectId: '$recordId' })
    wiredPacing({ error, data }) {
        this.isLoading = false;
        if (data) {
            this._data  = data;
            this._error = null;
        } else if (error) {
            this._error = error;
            this._data  = null;
        }
    }

    // ── Computed: display ─────────────────────────────────────────────────

    get hasData()  { return !!this._data; }
    get hasError() { return !!this._error; }

    get errorMessage() {
        if (!this._error) return '';
        return this._error.body ? this._error.body.message : JSON.stringify(this._error);
    }

    get goal()     { return this._data ? (this._data.goal     || 0) : 0; }
    get booked()   { return this._data ? (this._data.booked   || 0) : 0; }
    get pending()  { return this._data ? (this._data.pending  || 0) : 0; }
    get forecast() { return this._data ? (this._data.forecast || 0) : 0; }

    get formattedGoal()     { return USD_FMT.format(this.goal); }
    get formattedBooked()   { return USD_FMT.format(this.booked); }
    get formattedPending()  { return USD_FMT.format(this.pending); }
    get formattedForecast() { return USD_FMT.format(this.forecast); }

    get bookedPct()   { return this._pct(this.booked); }
    get pendingPct()  { return this._pct(this.pending); }
    get forecastPct() { return this._pct(this.forecast); }

    // ── Progress bar styles ───────────────────────────────────────────────

    get bookedBarStyle() {
        return `width: ${this._barWidth(this.booked)}%`;
    }

    get pendingBarStyle() {
        // pending bar starts where booked ends; clamp combined width to 100%
        const bookedW  = this._barWidth(this.booked);
        const pendingW = Math.min(this._barWidth(this.pending), 100 - bookedW);
        return `width: ${pendingW}%`;
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    _pct(amount) {
        if (!this.goal || this.goal === 0) return 0;
        return Math.round((amount / this.goal) * 100);
    }

    _barWidth(amount) {
        if (!this.goal || this.goal === 0) return 0;
        return Math.min(100, Math.round((amount / this.goal) * 100));
    }
}
