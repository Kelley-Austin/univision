import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import enqueueIngest from '@salesforce/apex/IngestTriggerController.enqueueIngest';

const FIELDS = ['Source_System__c.Last_Uploaded_At__c'];

export default class FileUploadSource extends LightningElement {
    @api recordId;
    @track isLoading = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    sourceSystemRecord;

    get lastUploadedAt() {
        return getFieldValue(this.sourceSystemRecord.data, 'Source_System__c.Last_Uploaded_At__c');
    }

    get formattedLastUploadedAt() {
        const val = this.lastUploadedAt;
        if (!val) return '';
        return new Date(val).toLocaleString();
    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        if (!uploadedFiles || uploadedFiles.length === 0) return;
        const contentVersionId = uploadedFiles[0].contentVersionId;
        this.isLoading = true;
        enqueueIngest({ contentVersionId, sourceSystemId: this.recordId })
            .then(() => {
                this.isLoading = false;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Upload queued',
                    message: 'File has been queued for processing.',
                    variant: 'success'
                }));
            })
            .catch(error => {
                this.isLoading = false;
                const msg = error && error.body ? error.body.message : 'Unknown error';
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Upload failed',
                    message: msg,
                    variant: 'error'
                }));
            });
    }
}
