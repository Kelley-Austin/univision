import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getRecentBatches from '@salesforce/apex/LoadBatchDashboardController.getRecentBatches';
import getSummary from '@salesforce/apex/LoadBatchDashboardController.getSummary';

const COLUMNS = [
    { label: 'Batch #', fieldName: 'Name' },
    { label: 'File Name', fieldName: 'File_Name__c' },
    { label: 'Status', fieldName: 'Status__c' },
    { label: 'Rows', fieldName: 'Row_Count__c', type: 'number' },
    { label: 'Errors', fieldName: 'Error_Count__c', type: 'number' },
    { label: 'Processed At', fieldName: 'Processed_At__c', type: 'date',
      typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' } }
];

export default class LoadBatchDashboard extends LightningElement {
    @api recordId;
    @track batches = [];
    @track summary;
    @track isLoading = false;
    columns = COLUMNS;
    _wiredBatchesResult;
    _wiredSummaryResult;

    @wire(getRecentBatches, { sourceSystemId: '$recordId', limitCount: 20 })
    wiredBatches(result) {
        this._wiredBatchesResult = result;
        if (result.data) this.batches = result.data;
        else if (result.error) this.showToast('Error', result.error.body?.message, 'error');
    }

    @wire(getSummary, { sourceSystemId: '$recordId' })
    wiredSummary(result) {
        this._wiredSummaryResult = result;
        if (result.data) this.summary = result.data;
    }

    handleRefresh() {
        this.isLoading = true;
        Promise.all([
            refreshApex(this._wiredBatchesResult),
            refreshApex(this._wiredSummaryResult)
        ]).finally(() => { this.isLoading = false; });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message: message || '', variant }));
    }
}
