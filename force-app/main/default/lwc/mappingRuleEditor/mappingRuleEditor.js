import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getMappingRules from '@salesforce/apex/IngestController.getMappingRules';
import saveMappingRule from '@salesforce/apex/IngestController.saveMappingRule';
import deleteMappingRule from '@salesforce/apex/IngestController.deleteMappingRule';
import dryRun from '@salesforce/apex/IngestController.dryRun';

export default class MappingRuleEditor extends LightningElement {
    @api recordId; // Source_System__c Id — set by record page context

    @track rules = [];
    @track showModal = false;
    @track editRule = {};
    @track dryRunResult;
    @track isEditMode = false;

    _wiredRulesResult;
    sourceSystemName = '';

    // Tracks the file the user dropped for dry run
    _pendingDocumentId;

    @wire(getMappingRules, { sourceSystemId: '$recordId' })
    wiredRules(result) {
        this._wiredRulesResult = result;
        if (result.data) {
            this.rules = result.data;
        } else if (result.error) {
            this.showToast('Error loading rules', result.error.body?.message, 'error');
        }
    }

    get hasRules() {
        return this.rules?.length > 0;
    }

    get modalTitle() {
        return this.isEditMode ? 'Edit Mapping Rule' : 'Add Mapping Rule';
    }

    get dryRunHasErrors() {
        return this.dryRunResult?.errors?.length > 0;
    }

    get selectedSourceId() {
        return this.recordId;
    }

    handleAddRule() {
        this.editRule = { Source_System__c: this.recordId, Is_Active__c: true };
        this.isEditMode = false;
        this.showModal = true;
    }

    handleEditRule(event) {
        const ruleId = event.currentTarget.dataset.id;
        this.editRule = { ...this.rules.find(r => r.Id === ruleId) };
        this.isEditMode = true;
        this.showModal = true;
    }

    async handleDeleteRule(event) {
        const ruleId = event.currentTarget.dataset.id;
        try {
            await deleteMappingRule({ ruleId });
            await refreshApex(this._wiredRulesResult);
            this.showToast('Deleted', 'Mapping rule removed.', 'success');
        } catch (error) {
            this.showToast('Delete failed', error.body?.message, 'error');
        }
    }

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.editRule = { ...this.editRule, [field]: event.detail.value };
    }

    handleModalCancel() {
        this.showModal = false;
        this.editRule = {};
    }

    async handleModalSave() {
        try {
            await saveMappingRule({ rule: this.editRule });
            await refreshApex(this._wiredRulesResult);
            this.showModal = false;
            this.showToast('Saved', 'Mapping rule saved successfully.', 'success');
        } catch (error) {
            this.showToast('Save failed', error.body?.message, 'error');
        }
    }

    async handleDryRun() {
        if (!this._pendingDocumentId) {
            this.showToast('No file selected', 'Upload a test file first to run the preview.', 'warning');
            return;
        }
        try {
            this.dryRunResult = await dryRun({
                contentDocumentId: this._pendingDocumentId,
                sourceSystemId: this.recordId
            });
        } catch (error) {
            this.showToast('Dry run failed', error.body?.message, 'error');
        }
    }

    /** Called by parent or by the sourceFileUpload LWC after a file upload */
    @api
    setDryRunDocument(contentDocumentId) {
        this._pendingDocumentId = contentDocumentId;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message: message ?? '', variant }));
    }
}
