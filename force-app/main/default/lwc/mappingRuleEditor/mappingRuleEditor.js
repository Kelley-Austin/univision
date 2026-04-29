import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getRules from '@salesforce/apex/MappingRuleService.getRules';
import saveRule from '@salesforce/apex/MappingRuleService.saveRule';
import deleteRule from '@salesforce/apex/MappingRuleService.deleteRule';
import activateRule from '@salesforce/apex/MappingRuleService.activateRule';
import dryRun from '@salesforce/apex/MappingRuleService.dryRun';

const COLUMNS = [
    { label: 'Rule Type', fieldName: 'Rule_Type__c' },
    { label: 'Field Name', fieldName: 'Field_Name__c' },
    { label: 'Raw Value', fieldName: 'Raw_Value__c' },
    { label: 'Mapped Value', fieldName: 'Mapped_Value__c' },
    { label: 'Active', fieldName: 'Is_Active__c', type: 'boolean' },
    { label: 'Notes', fieldName: 'Notes__c' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Delete', name: 'delete' },
                { label: 'Toggle Active', name: 'toggle' }
            ]
        }
    }
];

export default class MappingRuleEditor extends LightningElement {
    @api recordId;
    @track rules = [];
    @track showModal = false;
    @track editRecord = {};
    @track dryRunResult;
    @track isLoading = false;
    _wiredResult;
    columns = COLUMNS;

    ruleTypeOptions = [
        { label: 'Exclude', value: 'Exclude' },
        { label: 'Map', value: 'Map' }
    ];

    @wire(getRules, { sourceSystemId: '$recordId' })
    wiredRules(result) {
        this._wiredResult = result;
        if (result.data) this.rules = result.data;
        else if (result.error) this.showToast('Error', result.error.body?.message, 'error');
    }

    get modalTitle() {
        return this.editRecord.Id ? 'Edit Rule' : 'New Rule';
    }

    handleNew() {
        this.editRecord = { Source_System__c: this.recordId, Is_Active__c: false };
        this.showModal = true;
    }

    handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'edit') {
            this.editRecord = Object.assign({}, row);
            this.showModal = true;
        } else if (action === 'delete') {
            deleteRule({ ruleId: row.Id })
                .then(() => refreshApex(this._wiredResult))
                .then(() => this.showToast('Deleted', 'Rule removed.', 'success'))
                .catch(e => this.showToast('Error', e.body?.message, 'error'));
        } else if (action === 'toggle') {
            activateRule({ ruleId: row.Id, isActive: !row.Is_Active__c })
                .then(() => refreshApex(this._wiredResult))
                .catch(e => this.showToast('Error', e.body?.message, 'error'));
        }
    }

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.editRecord = Object.assign({}, this.editRecord, { [field]: event.detail.value });
    }

    handleCheckboxChange(event) {
        const field = event.currentTarget.dataset.field;
        this.editRecord = Object.assign({}, this.editRecord, { [field]: event.target.checked });
    }

    handleModalClose() {
        this.showModal = false;
        this.editRecord = {};
    }

    handleSave() {
        saveRule({ rule: this.editRecord })
            .then(() => refreshApex(this._wiredResult))
            .then(() => {
                this.showModal = false;
                this.showToast('Saved', 'Rule saved.', 'success');
            })
            .catch(e => this.showToast('Error', e.body?.message, 'error'));
    }

    handleDryRun() {
        this.isLoading = true;
        dryRun({ sourceSystemId: this.recordId })
            .then(result => {
                this.dryRunResult = result;
                this.isLoading = false;
                this.showToast(
                    'Dry Run Complete',
                    `${result.wouldExclude} rows would be excluded, ${result.wouldRemap} remapped.`,
                    'info'
                );
            })
            .catch(e => {
                this.isLoading = false;
                this.showToast('Error', e.body?.message, 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message: message || '', variant }));
    }
}
