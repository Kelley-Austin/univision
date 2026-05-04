import { LightningElement, track } from 'lwc';
import runReport from '@salesforce/apex/FinancialReportController.runReport';

const MONTH_OPTIONS = [
    { label: 'Jan', value: '1'  }, { label: 'Feb', value: '2'  },
    { label: 'Mar', value: '3'  }, { label: 'Apr', value: '4'  },
    { label: 'May', value: '5'  }, { label: 'Jun', value: '6'  },
    { label: 'Jul', value: '7'  }, { label: 'Aug', value: '8'  },
    { label: 'Sep', value: '9'  }, { label: 'Oct', value: '10' },
    { label: 'Nov', value: '11' }, { label: 'Dec', value: '12' }
];

const GROUP_BY_OPTIONS = [
    { label: 'Account',      value: 'ACCOUNT'      },
    { label: 'Category',     value: 'CATEGORY'     },
    { label: 'Revenue Type', value: 'REVENUE_TYPE' },
    { label: 'Month',        value: 'MONTH'        }
];

const ALL_COLUMNS = [
    { field: 'groupLabel',       label: 'Group',          type: 'text',     visible: true  },
    { field: 'booked',           label: 'Booked',         type: 'currency', visible: true  },
    { field: 'pending',          label: 'Pending',        type: 'currency', visible: true  },
    { field: 'weightedForecast', label: 'Wtd Forecast',   type: 'currency', visible: true  },
    { field: 'budget',           label: 'Budget',         type: 'currency', visible: true  },
    { field: 'lastYearActual',   label: 'LY Actual',      type: 'currency', visible: true  },
    { field: 'currentActual',    label: 'Actual',         type: 'currency', visible: false },
    { field: 'vsBudgetAmt',      label: 'vs Budget $',    type: 'currency', visible: true  },
    { field: 'vsBudgetPctFmt',   label: 'vs Budget %',    type: 'text',     visible: true  },
    { field: 'vsLastYearAmt',    label: 'vs LY $',        type: 'currency', visible: false },
    { field: 'vsLastYearPctFmt', label: 'vs LY %',        type: 'text',     visible: true  }
];

export default class FinancialReportBuilder extends LightningElement {
    @track rows          = [];
    @track columnToggles = ALL_COLUMNS.map(c => ({ ...c }));
    @track isLoading     = false;
    @track errorMessage;

    config = {
        periodYear:  new Date().getFullYear(),
        fromMonth:   '1',
        toMonth:     '12',
        groupBy:     'ACCOUNT',
        revenueType: ''
    };

    monthOptions   = MONTH_OPTIONS;
    groupByOptions = GROUP_BY_OPTIONS;

    handleYearChange(e)     { this.config = { ...this.config, periodYear:  parseInt(e.detail.value, 10) }; }
    handleFromMonthChange(e){ this.config = { ...this.config, fromMonth:   e.detail.value }; }
    handleToMonthChange(e)  { this.config = { ...this.config, toMonth:     e.detail.value }; }
    handleGroupByChange(e)  { this.config = { ...this.config, groupBy:     e.detail.value }; }
    handleRevTypeChange(e)  { this.config = { ...this.config, revenueType: e.detail.value }; }

    handleColumnToggle(e) {
        const field = e.target.dataset.field;
        this.columnToggles = this.columnToggles.map(c =>
            c.field === field ? { ...c, visible: e.detail.checked } : c
        );
    }

    async handleRun() {
        this.isLoading    = true;
        this.errorMessage = undefined;
        try {
            const cfg = {
                periodYear:  this.config.periodYear,
                fromMonth:   parseInt(this.config.fromMonth, 10),
                toMonth:     parseInt(this.config.toMonth, 10),
                groupBy:     this.config.groupBy,
                revenueType: this.config.revenueType || null
            };
            const raw = await runReport({ configJson: JSON.stringify(cfg) });
            this.rows = raw.map(r => ({
                ...r,
                vsBudgetPctFmt:   r.vsBudgetPct   != null ? r.vsBudgetPct.toFixed(1)   + '%' : '—',
                vsLastYearPctFmt: r.vsLastYearPct != null ? r.vsLastYearPct.toFixed(1) + '%' : '—'
            }));
        } catch (err) {
            this.errorMessage = err.body?.message ?? 'Report failed.';
        } finally {
            this.isLoading = false;
        }
    }

    handleExport() {
        const visible  = this.columnToggles.filter(c => c.visible);
        const headers  = visible.map(c => c.label).join(',');
        const csv = [headers, ...this.rows.map(r =>
            visible.map(c => {
                const v = r[c.field] ?? '';
                return typeof v === 'string' && v.includes(',') ? `"${v}"` : v;
            }).join(',')
        )].join('\n');

        const a = document.createElement('a');
        a.href     = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        a.download = `financial-report-${this.config.periodYear}.csv`;
        a.click();
    }

    get visibleColumns() {
        return this.columnToggles
            .filter(c => c.visible)
            .map(c => ({
                label:       c.label,
                fieldName:   c.field,
                type:        c.type,
                cellAttributes: c.type === 'currency' || c.field === 'vsBudgetPctFmt' || c.field === 'vsLastYearPctFmt'
                    ? { alignment: 'right' }
                    : undefined
            }));
    }

    get hasError() { return !!this.errorMessage; }
    get hasData()  { return !this.isLoading && !this.hasError && this.rows.length > 0; }
    get isEmpty()  { return !this.isLoading && !this.hasError && this.rows.length === 0; }
    get noData()   { return this.rows.length === 0; }
}
