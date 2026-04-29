import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getBudgetGridData from '@salesforce/apex/ProjectionService.getBudgetGridData';
import getActiveCategories from '@salesforce/apex/CategoryService.getActiveCategories';

const MONTH_LABELS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const REVENUE_TYPE_OPTIONS = [
    { label: '(All)',        value: ''            },
    { label: 'National TV',  value: 'National TV' },
    { label: 'Local TV',     value: 'Local TV'    },
    { label: 'Digital',      value: 'Digital'     },
    { label: 'Radio',        value: 'Radio'       },
    { label: 'Streaming',    value: 'Streaming'   },
    { label: 'Other',        value: 'Other'       }
];

const fmt = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });

export default class AccountBudgetGrid extends LightningElement {
    @api accountId;

    @track revenueType  = '';
    @track categoryId   = '';
    @track periodYear   = new Date().getFullYear();
    @track errorMessage = '';
    @track isLoading    = false;
    @track categoryOptions = [{ label: '(All)', value: '' }];

    _wireGridResult;
    _rawRows = [];

    // ── Static options ────────────────────────────────────────────────────────

    get revenueTypeOptions() { return REVENUE_TYPE_OPTIONS; }
    get monthHeaders()       { return MONTH_LABELS; }

    // ── Computed states ───────────────────────────────────────────────────────

    get isEmpty() { return !this._rawRows || this._rawRows.length === 0; }

    get displayRows() {
        return this._rawRows.map((row, idx) => {
            const budAmts  = this._toDisplayAmounts(row.budgetAmounts,     false);
            const projAmts = this._toDisplayAmounts(row.projectionAmounts, false);
            const actAmts  = this._toDisplayAmounts(row.actualAmounts,     false);
            const varAmts  = this._toDisplayAmounts(row.varianceAmounts,   true);

            return {
                budgetKey:     `bud-${idx}`,
                projectionKey: `proj-${idx}`,
                actualKey:     `act-${idx}`,
                varianceKey:   `var-${idx}`,
                categoryName:  row.categoryName,
                revenueType:   row.revenueType,
                budgetAmounts:     budAmts,
                projectionAmounts: projAmts,
                actualAmounts:     actAmts,
                varianceAmounts:   varAmts,
                formattedBudgetTotal:     fmt.format(row.totalBudget     || 0),
                formattedProjectionTotal: fmt.format(row.totalProjection || 0),
                formattedActualTotal:     fmt.format(row.totalActual     || 0),
                formattedVarianceTotal:   fmt.format(row.totalVariance   || 0),
                varianceTotalClass: 'total-cell ' + (row.totalVariance >= 0 ? 'positive' : 'negative')
            };
        });
    }

    // ── Wires ─────────────────────────────────────────────────────────────────

    @wire(getActiveCategories)
    wiredCategories({ error, data }) {
        if (data) {
            const opts = data.map(c => ({ label: c.Name, value: c.Id }));
            this.categoryOptions = [{ label: '(All)', value: '' }, ...opts];
        }
    }

    @wire(getBudgetGridData, {
        accountId:   '$accountId',
        categoryId:  '$categoryId',
        revenueType: '$revenueType',
        periodYear:  '$periodYear'
    })
    wiredGrid(result) {
        this._wireGridResult = result;
        this.isLoading = false;
        const { error, data } = result;
        if (data) {
            this._rawRows = data;
            this.errorMessage = '';
        } else if (error) {
            this.errorMessage = 'Failed to load budget data: ' + this._extractError(error);
            this._rawRows = [];
        }
    }

    // ── Event handlers ────────────────────────────────────────────────────────

    handleRevenueTypeChange(event) { this.revenueType  = event.detail.value; this.isLoading = true; }
    handleCategoryChange(event)    { this.categoryId   = event.detail.value; this.isLoading = true; }
    handleYearChange(event)        { this.periodYear   = parseInt(event.detail.value, 10); this.isLoading = true; }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this._wireGridResult).finally(() => { this.isLoading = false; });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _toDisplayAmounts(amounts, isVariance) {
        if (!amounts || !amounts.length) {
            return MONTH_LABELS.map((_, i) => ({ idx: i, formatted: '$0', cssClass: 'amount-cell' }));
        }
        return amounts.map((v, i) => {
            const val = v || 0;
            const cssClass = isVariance
                ? 'amount-cell ' + (val >= 0 ? 'positive' : 'negative')
                : 'amount-cell';
            return { idx: i, formatted: fmt.format(val), cssClass };
        });
    }

    _extractError(err) {
        if (typeof err === 'string')    { return err; }
        if (err?.body?.message)         { return err.body.message; }
        if (err?.message)               { return err.message; }
        return JSON.stringify(err);
    }
}
