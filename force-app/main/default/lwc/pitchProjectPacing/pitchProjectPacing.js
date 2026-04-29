import { LightningElement, api, wire } from 'lwc';
import getPacingData from '@salesforce/apex/PitchProjectController.getPacingData';

const FMT = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });

function fmt(val) { return FMT.format(val || 0); }
function pct(part, total) {
    if (!total || total === 0) return 0;
    return Math.min(Math.round((part / total) * 100), 100);
}

export default class PitchProjectPacing extends LightningElement {

    @api recordId;

    _data   = null;
    _error  = null;

    @wire(getPacingData, { projectId: '$recordId' })
    wiredPacing({ data, error }) {
        if (data)  { this._data = data;  this._error = null; }
        if (error) { this._error = error.body?.message || 'Error loading pacing data'; this._data = null; }
    }

    // ── state gates ───────────────────────────────────────────────────────

    get isLoading()   { return !this._data && !this._error; }
    get hasError()    { return !!this._error; }
    get hasData()     { return !!this._data; }
    get errorMessage(){ return this._error; }

    // ── formatted values ─────────────────────────────────────────────────

    get formattedGoal()    { return fmt(this._data?.goal); }
    get formattedBooked()  { return fmt(this._data?.booked); }
    get formattedPending() { return fmt(this._data?.pending); }
    get formattedForecast(){ return fmt(this._data?.forecast); }

    // ── progress bar ──────────────────────────────────────────────────────

    get bookedPct()  { return pct(this._data?.booked,  this._data?.goal); }
    get pendingPct() { return pct(this._data?.pending, this._data?.goal); }

    get bookedBarStyle()  { return `width:${this.bookedPct}%;background:#2e844a;height:12px;display:inline-block;`; }
    get pendingBarStyle() { return `width:${this.pendingPct}%;background:#f59e0b;height:12px;display:inline-block;`; }

    get bookedBarLabel()  { return `Booked: ${this.formattedBooked} (${this.bookedPct}% of goal)`; }
    get pendingBarLabel() { return `Pending: ${this.formattedPending} (${this.pendingPct}% of goal)`; }
}
