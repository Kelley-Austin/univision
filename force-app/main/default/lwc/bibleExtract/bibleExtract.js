import { LightningElement, track } from 'lwc';
import getBibleData from '@salesforce/apex/BibleExportController.getBibleData';

const MONTH_OPTIONS = [
    { label: 'Jan', value: '1'  }, { label: 'Feb', value: '2'  },
    { label: 'Mar', value: '3'  }, { label: 'Apr', value: '4'  },
    { label: 'May', value: '5'  }, { label: 'Jun', value: '6'  },
    { label: 'Jul', value: '7'  }, { label: 'Aug', value: '8'  },
    { label: 'Sep', value: '9'  }, { label: 'Oct', value: '10' },
    { label: 'Nov', value: '11' }, { label: 'Dec', value: '12' }
];

const COLUMNS = [
    { label: 'Account',          fieldName: 'accountName',      type: 'text',     initialWidth: 180 },
    { label: 'Category',         fieldName: 'categoryName',     type: 'text',     initialWidth: 140 },
    { label: 'Rev Type',         fieldName: 'revenueType',      type: 'text',     initialWidth: 100 },
    { label: 'Period',           fieldName: 'periodLabel',      type: 'text',     initialWidth: 80 },
    { label: 'Booked',           fieldName: 'booked',           type: 'currency', cellAttributes: { alignment: 'right' } },
    { label: 'Pending',          fieldName: 'pending',          type: 'currency', cellAttributes: { alignment: 'right' } },
    { label: 'Wtd Forecast',     fieldName: 'weightedForecast', type: 'currency', cellAttributes: { alignment: 'right' } },
    { label: 'Budget',           fieldName: 'budget',           type: 'currency', cellAttributes: { alignment: 'right' } },
    { label: 'LY Actual',        fieldName: 'lastYearActual',   type: 'currency', cellAttributes: { alignment: 'right' } },
    { label: 'Current Actual',   fieldName: 'currentActual',    type: 'currency', cellAttributes: { alignment: 'right' } },
    { label: 'vs Budget $',      fieldName: 'vsBudgetAmt',      type: 'currency', cellAttributes: { alignment: 'right' } },
    { label: 'vs Budget %',      fieldName: 'vsBudgetPctFmt',   type: 'text',     cellAttributes: { alignment: 'right' } },
    { label: 'vs LY $',          fieldName: 'vsLastYearAmt',    type: 'currency', cellAttributes: { alignment: 'right' } },
    { label: 'vs LY %',          fieldName: 'vsLastYearPctFmt', type: 'text',     cellAttributes: { alignment: 'right' } }
];

export default class BibleExtract extends LightningElement {
    @track rows         = [];
    @track isLoading    = false;
    @track errorMessage;

    filterYear      = new Date().getFullYear();
    filterFromMonth = '1';
    filterToMonth   = '12';
    filterRevType   = '';
    snapshotLabel   = '';

    columns      = COLUMNS;
    monthOptions = MONTH_OPTIONS;

    handleYearChange(e)      { this.filterYear      = parseInt(e.detail.value, 10); }
    handleFromMonthChange(e) { this.filterFromMonth = e.detail.value; }
    handleToMonthChange(e)   { this.filterToMonth   = e.detail.value; }
    handleRevTypeChange(e)   { this.filterRevType   = e.detail.value; }

    async handleRun() {
        this.isLoading    = true;
        this.errorMessage = undefined;
        try {
            const raw = await getBibleData({
                periodYear:  this.filterYear,
                fromMonth:   parseInt(this.filterFromMonth, 10),
                toMonth:     parseInt(this.filterToMonth, 10),
                accountId:   null,
                categoryId:  null,
                revenueType: this.filterRevType || null
            });
            this.rows = raw.map((r, i) => ({
                ...r,
                rowKey:         i,
                vsBudgetPctFmt:   r.vsBudgetPct   != null ? r.vsBudgetPct.toFixed(1)   + '%' : '—',
                vsLastYearPctFmt: r.vsLastYearPct != null ? r.vsLastYearPct.toFixed(1) + '%' : '—'
            }));
            this.snapshotLabel = raw.length > 0 ? (raw[0].periodLabel ?? '') : '';
        } catch (err) {
            this.errorMessage = err.body?.message ?? 'Failed to load Bible data.';
        } finally {
            this.isLoading = false;
        }
    }

    handleExport() {
        const headers = COLUMNS.map(c => c.label).join(',');
        const fields  = ['accountName','categoryName','revenueType','periodLabel',
                         'booked','pending','weightedForecast','budget',
                         'lastYearActual','currentActual',
                         'vsBudgetAmt','vsBudgetPctFmt','vsLastYearAmt','vsLastYearPctFmt'];
        const csv = [headers, ...this.rows.map(r =>
            fields.map(f => {
                const v = r[f] ?? '';
                return typeof v === 'string' && v.includes(',') ? `"${v}"` : v;
            }).join(',')
        )].join('\n');

        const a = document.createElement('a');
        a.href     = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        a.download = `the-bible-${this.filterYear}.csv`;
        a.click();
    }

    get hasError() { return !!this.errorMessage; }
    get hasData()  { return !this.isLoading && !this.hasError && this.rows.length > 0; }
    get isEmpty()  { return !this.isLoading && !this.hasError && this.rows.length === 0; }
    get noData()   { return this.rows.length === 0; }
}
