import { LightningElement, track, wire } from 'lwc';
import getExcludedRows     from '@salesforce/apex/ExclusionLogController.getExcludedRows';
import requeueRows         from '@salesforce/apex/ExclusionLogController.requeueRows';
import getExclusionRuleOptions from '@salesforce/apex/ExclusionLogController.getExclusionRuleOptions';
import { ShowToastEvent }  from 'lightning/platformShowToastEvent';

const PAGE_SIZE = 50;

const COLUMNS = [
    { label: 'Advertiser Name',  fieldName: 'rawAdvertiserName',  type: 'text' },
    { label: 'Advertiser Code',  fieldName: 'rawAdvertiserCode',  type: 'text' },
    { label: 'Revenue Amount',   fieldName: 'revenueAmount',      type: 'currency', cellAttributes: { alignment: 'right' } },
    { label: 'Revenue Type',     fieldName: 'revenueType',        type: 'text' },
    { label: 'Year',             fieldName: 'periodYear',         type: 'number', cellAttributes: { alignment: 'center' } },
    { label: 'Month',            fieldName: 'periodMonth',        type: 'number', cellAttributes: { alignment: 'center' } },
    { label: 'Excluding Rule',   fieldName: 'excludingRule',      type: 'text' },
    { label: 'Source System',    fieldName: 'sourceSystem',       type: 'text' },
    { label: 'External Key',     fieldName: 'externalKey',        type: 'text' },
    { label: 'Created',          fieldName: 'createdDate',        type: 'text' }
];

export default class ExclusionLogListView extends LightningElement {
    @track rows         = [];
    @track ruleOptions  = [{ label: 'All Rules', value: '' }];
    @track isLoading    = true;
    @track errorMessage;
    @track selectedIds  = [];
    draftValues         = [];

    filterRule  = '';
    filterYear  = null;
    currentPage = 1;
    hasMorePages = false;

    columns = COLUMNS;

    @wire(getExclusionRuleOptions)
    wiredRules({ data, error }) {
        if (data) {
            this.ruleOptions = [{ label: 'All Rules', value: '' },
                ...data.filter(r => r).map(r => ({ label: r, value: r }))];
        }
    }

    connectedCallback() {
        this._load();
    }

    async _load() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const offset = (this.currentPage - 1) * PAGE_SIZE;
            const data = await getExcludedRows({
                pageSize:     PAGE_SIZE + 1,
                pageOffset:   offset,
                excludingRule: this.filterRule || null,
                periodYear:    this.filterYear ? parseInt(this.filterYear, 10) : null
            });
            this.hasMorePages = data.length > PAGE_SIZE;
            this.rows = this.hasMorePages ? data.slice(0, PAGE_SIZE) : data;
        } catch (err) {
            this.errorMessage = err.body?.message ?? 'Failed to load exclusion log.';
        } finally {
            this.isLoading = false;
        }
    }

    handleRuleChange(e)  { this.filterRule = e.detail.value; }
    handleYearChange(e)  { this.filterYear = e.detail.value; }
    handleApply()        { this.currentPage = 1; this._load(); }

    handlePrev() { if (this.currentPage > 1) { this.currentPage--; this._load(); } }
    handleNext() { if (this.hasMorePages)    { this.currentPage++; this._load(); } }

    handleRowSelection(e) {
        this.selectedIds = e.detail.selectedRows.map(r => r.stagingId);
    }

    async handleRequeue() {
        if (!this.selectedIds.length) { return; }
        this.isLoading = true;
        try {
            await requeueRows({ stagingIds: this.selectedIds });
            this.selectedIds = [];
            this.dispatchEvent(new ShowToastEvent({
                title:   'Re-queued',
                message: this.selectedIds.length + ' row(s) set to Pending for re-reconciliation.',
                variant: 'success'
            }));
            this._load();
        } catch (err) {
            this.isLoading = false;
            this.dispatchEvent(new ShowToastEvent({
                title:   'Re-queue Failed',
                message: err.body?.message ?? 'Unexpected error.',
                variant: 'error'
            }));
        }
    }

    get noSelection() { return this.selectedIds.length === 0; }
    get hasError()    { return !!this.errorMessage; }
    get hasData()     { return !this.isLoading && !this.hasError && this.rows.length > 0; }
    get isEmpty()     { return !this.isLoading && !this.hasError && this.rows.length === 0; }
    get isFirstPage() { return this.currentPage <= 1; }
    get isLastPage()  { return !this.hasMorePages; }
}
