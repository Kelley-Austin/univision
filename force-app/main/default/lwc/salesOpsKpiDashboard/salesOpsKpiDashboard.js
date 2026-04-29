import { LightningElement, track } from 'lwc';
import getKpiData from '@salesforce/apex/SalesOpsKpiController.getKpiData';

const CURRENCY_FMT = new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD', maximumFractionDigits: 0
});

export default class SalesOpsKpiDashboard extends LightningElement {
    @track tiles       = [];
    @track isLoading   = true;
    @track errorMessage;

    connectedCallback() {
        this._load();
    }

    async _load() {
        this.isLoading = true;
        try {
            const d = await getKpiData();
            this.errorMessage = undefined;
            this.tiles = this._buildTiles(d);
        } catch (err) {
            this.errorMessage = err.body?.message ?? 'Failed to load KPI data.';
        } finally {
            this.isLoading = false;
        }
    }

    get hasError() { return !!this.errorMessage; }
    get hasData()  { return !this.isLoading && !this.hasError; }

    _buildTiles(d) {
        const pct   = d.budgetAttainmentPct != null ? d.budgetAttainmentPct.toFixed(1) + '%' : '—';
        const alert = d.budgetAttainmentPct != null && d.budgetAttainmentPct < 80;
        return [
            {
                id:           'booked',
                label:        'Booked MTD',
                value:        CURRENCY_FMT.format(d.bookedMtd ?? 0),
                icon:         'utility:money',
                iconVariant:  'default',
                cardClass:    'kpi-tile slds-box',
                subLabel:     null,
                alertMessage: null
            },
            {
                id:           'forecast',
                label:        'Weighted Forecast',
                value:        CURRENCY_FMT.format(d.weightedForecast ?? 0),
                icon:         'utility:chart',
                iconVariant:  'default',
                cardClass:    'kpi-tile slds-box',
                subLabel:     null,
                alertMessage: null
            },
            {
                id:           'budget',
                label:        'Budget Attainment',
                value:        pct,
                icon:         alert ? 'utility:warning' : 'utility:check',
                iconVariant:  alert ? 'warning' : 'default',
                cardClass:    `kpi-tile slds-box${alert ? ' kpi-tile--alert' : ''}`,
                subLabel:     null,
                alertMessage: alert ? 'Below 80% attainment' : null
            },
            {
                id:           'reconciliations',
                label:        'Open Reconciliations',
                value:        d.openReconciliations ?? 0,
                icon:         d.openReconciliations > 0 ? 'utility:error' : 'utility:check',
                iconVariant:  d.openReconciliations > 0 ? 'error' : 'default',
                cardClass:    `kpi-tile slds-box${d.openReconciliations > 0 ? ' kpi-tile--alert' : ''}`,
                subLabel:     null,
                alertMessage: d.openReconciliations > 0 ? 'Rows awaiting matching' : null
            },
            {
                id:           'lateActuals',
                label:        'Late Actuals',
                value:        d.lateActualsCount ?? 0,
                icon:         d.lateActualsCount > 0 ? 'utility:clock' : 'utility:check',
                iconVariant:  d.lateActualsCount > 0 ? 'warning' : 'default',
                cardClass:    `kpi-tile slds-box${d.lateActualsCount > 0 ? ' kpi-tile--warn' : ''}`,
                subLabel:     null,
                alertMessage: d.lateActualsCount > 0 ? 'Pending AE review' : null
            },
            {
                id:           'period',
                label:        'Period Status',
                value:        d.periodStatus ?? '—',
                icon:         this._periodIcon(d.periodStatus),
                iconVariant:  'default',
                cardClass:    'kpi-tile slds-box',
                subLabel:     d.periodYear && d.periodMonth
                    ? this._monthName(d.periodMonth) + ' ' + d.periodYear
                    : null,
                alertMessage: null
            }
        ];
    }

    _periodIcon(status) {
        if (status === 'Closed')   { return 'utility:lock'; }
        if (status === 'Reopened') { return 'utility:refresh'; }
        return 'utility:calendar';
    }

    _monthName(mo) {
        const names = ['Jan','Feb','Mar','Apr','May','Jun',
                       'Jul','Aug','Sep','Oct','Nov','Dec'];
        return names[(mo ?? 1) - 1] ?? '';
    }
}
