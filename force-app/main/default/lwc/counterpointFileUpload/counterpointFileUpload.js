import { LightningElement, api, track } from 'lwc';
import importCsvFromLwc from '@salesforce/apex/CounterpointIngestionService.importCsvFromLwc';

const DATE_TYPE_OPTIONS = [
    { label: 'Calendar  — Period column is MM/YYYY or YYYY-MM', value: 'Calendar' },
    { label: 'Broadcast — Period column is "WK OF MM/DD/YY" or broadcast month', value: 'Broadcast' }
];

const ACCEPTED_FORMATS = ['.csv', '.txt'];

export default class CounterpointFileUpload extends LightningElement {

    // ── Flow input ────────────────────────────────────────────────────────
    /** ID of the Advertising_Opportunity__c record that launched the quick action. */
    @api recordId;

    // ── Flow outputs (set after import attempt) ───────────────────────────
    @api uploadSuccess  = false;
    @api importBatchId  = '';
    @api totalRows      = 0;
    @api validRows      = 0;
    @api invalidRows    = 0;
    @api errorMessage   = '';

    // ── Internal state ────────────────────────────────────────────────────
    @track selectedDateType = 'Calendar';
    @track isProcessing     = false;
    @track isComplete       = false;
    @track hasError         = false;
    @track hasAttempted     = false;

    // ── Getters ───────────────────────────────────────────────────────────
    get dateTypeOptions()  { return DATE_TYPE_OPTIONS; }
    get acceptedFormats()  { return ACCEPTED_FORMATS; }

    // ── Event handlers ────────────────────────────────────────────────────
    handleDateTypeChange(evt) {
        this.selectedDateType = evt.detail.value;
    }

    handleUploadFinished(evt) {
        const files = evt.detail.files;
        if (!files || files.length === 0) return;

        const contentDocumentId = files[0].documentId;

        this.isProcessing = true;
        this.hasError     = false;
        this.errorMessage = '';

        importCsvFromLwc({
            contentDocumentId,
            dateType:      this.selectedDateType,
            opportunityId: this.recordId || null
        })
        .then(result => {
            this.isProcessing  = false;
            this.hasAttempted  = true;

            if (result.success) {
                this.uploadSuccess = true;
                this.importBatchId = result.importBatchId;
                this.totalRows     = result.totalRows     || 0;
                this.validRows     = result.validRows     || 0;
                this.invalidRows   = result.invalidRows   || 0;
                this.isComplete    = true;
            } else {
                this.hasError      = true;
                this.uploadSuccess = false;
                this.errorMessage  = result.errorMessage || 'An unexpected error occurred.';
            }
        })
        .catch(err => {
            this.isProcessing  = false;
            this.hasAttempted  = true;
            this.hasError      = true;
            this.uploadSuccess = false;
            this.errorMessage  = (err.body && err.body.message) ? err.body.message : err.message;
        });
    }

    // ── Screen Flow validation ────────────────────────────────────────────
    /**
     * Called by the Screen Flow runtime when the user clicks Next/Finish.
     * Blocks navigation while processing or before any import has been attempted.
     * Allows navigation after a completed attempt (success or failure) so the
     * flow can route to the appropriate success or error screen.
     */
    @api
    validate() {
        if (this.isProcessing) {
            return { isValid: false, errorMessage: 'Your file is still being processed. Please wait.' };
        }
        if (!this.hasAttempted) {
            return {
                isValid: false,
                errorMessage: 'Please upload a Counterpoint CSV file to continue.'
            };
        }
        return { isValid: true };
    }
}
