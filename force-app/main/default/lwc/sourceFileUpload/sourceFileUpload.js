import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActiveSources from '@salesforce/apex/IngestController.getActiveSources';
import processUpload from '@salesforce/apex/IngestController.processUpload';

export default class SourceFileUpload extends LightningElement {
    @api recordId; // Source_System__c record Id (when placed on a record page)

    @track selectedSourceId;
    @track result;
    @track isLoading = false;

    acceptedFormats = ['.csv', '.txt', '.tsv'];

    sourceSystems = [];

    @wire(getActiveSources)
    wiredSources({ data, error }) {
        if (data) {
            this.sourceSystems = data;
            // Auto-select if on a Source System record page
            if (this.recordId) {
                this.selectedSourceId = this.recordId;
            }
        } else if (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading source systems',
                message: error.body?.message ?? 'Unknown error',
                variant: 'error'
            }));
        }
    }

    get sourceOptions() {
        return this.sourceSystems.map(s => ({
            label: s.Name + ' (' + s.Source_Code__c + ')',
            value: s.Id
        }));
    }

    get resultClass() {
        if (!this.result) return '';
        return this.result.errors?.length > 0
            ? 'slds-box slds-theme_warning slds-m-top_medium'
            : 'slds-box slds-theme_success slds-m-top_medium';
    }

    get hasErrors() {
        return this.result?.errors?.length > 0;
    }

    handleSourceChange(event) {
        this.selectedSourceId = event.detail.value;
        this.result = null;
    }

    async handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        if (!uploadedFiles?.length) return;

        const contentDocumentId = uploadedFiles[0].documentId;
        this.isLoading = true;
        this.result = null;

        try {
            this.result = await processUpload({
                contentDocumentId,
                sourceSystemId: this.selectedSourceId
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Upload complete',
                message: `${this.result.totalRows} rows processed (${this.result.pendingRows} pending, ${this.result.excludedRows} excluded)`,
                variant: this.result.errors?.length > 0 ? 'warning' : 'success'
            }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Upload failed',
                message: error.body?.message ?? error.message ?? 'Unknown error',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }
}
