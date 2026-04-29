import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';
import getActiveOutlets from '@salesforce/apex/PitchProjectController.getActiveOutlets';
import saveProject from '@salesforce/apex/PitchProjectController.saveProject';

const OWNER_TYPE_OPTIONS = [
    { label: 'Corporate', value: 'Corporate' },
    { label: 'Market',    value: 'Market' }
];

export default class PitchProjectCreator extends NavigationMixin(LightningElement) {

    @track currentStep = 1;
    @track isLoading = false;
    @track saveError = null;

    @track project = {
        name:          '',
        ownerType:     '',
        owningMarketId: null,
        timeFrame:     '',
        goal:          null,
        startDate:     null,
        endDate:       null,
        description:   ''
    };

    @track selectedOutletIds = [];
    @track outletUnitCodeRows = [];  // [{ outletId, outletName, unitCodes }]

    outlets = [];
    outletsLoading = true;
    outletsError = null;

    @wire(getActiveOutlets)
    wiredOutlets({ data, error }) {
        this.outletsLoading = false;
        if (data) {
            this.outlets = data;
        } else if (error) {
            this.outletsError = error.body?.message || 'Error loading outlets';
        }
    }

    // ── computed ──────────────────────────────────────────────────────────

    get ownerTypeOptions() { return OWNER_TYPE_OPTIONS; }

    get currentStepStr() { return String(this.currentStep); }

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }

    get isMarketOwner() { return this.project.ownerType === 'Market'; }

    get outletOptions() {
        return this.outlets.map(o => ({ label: o.Name, value: o.Id }));
    }

    get hasOutlets() { return this.selectedOutletIds.length > 0; }

    get backButtonClass() { return this.currentStep === 1 ? 'slds-hide' : ''; }

    get formattedGoal() {
        if (!this.project.goal) return '$0.00';
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' })
            .format(this.project.goal);
    }

    get totalUnitCodeCount() {
        return this.outletUnitCodeRows.reduce((sum, row) => {
            const codes = row.unitCodes ? row.unitCodes.split(',').filter(c => c.trim()) : [];
            return sum + codes.length;
        }, 0);
    }

    // ── event handlers ────────────────────────────────────────────────────

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        let val = event.target.value;
        if (field === 'goal') val = parseFloat(val) || null;
        this.project = { ...this.project, [field]: val };
    }

    handleMarketChange(event) {
        this.project = { ...this.project, owningMarketId: event.detail.value };
    }

    handleOutletSelection(event) {
        this.selectedOutletIds = event.detail.value;
    }

    handleUnitCodeChange(event) {
        const outletId = event.target.dataset.outletId;
        this.outletUnitCodeRows = this.outletUnitCodeRows.map(row =>
            row.outletId === outletId
                ? { ...row, unitCodes: event.target.value }
                : row
        );
    }

    handleNext() {
        if (!this._validateCurrentStep()) return;
        if (this.currentStep === 2) this._syncOutletRows();
        this.currentStep += 1;
    }

    handleBack() {
        if (this.currentStep > 1) {
            this.saveError = null;
            this.currentStep -= 1;
        }
    }

    async handleSave() {
        this.isLoading = true;
        this.saveError = null;

        const outletIds = [];
        const unitCodes = [];

        for (const row of this.outletUnitCodeRows) {
            const codes = row.unitCodes
                ? row.unitCodes.split(',').map(c => c.trim()).filter(Boolean)
                : [];
            for (const code of codes) {
                outletIds.push(row.outletId);
                unitCodes.push(code);
            }
        }

        try {
            const projId = await saveProject({
                projectName:    this.project.name,
                ownerType:      this.project.ownerType,
                owningMarketId: this.project.owningMarketId,
                timeFrame:      this.project.timeFrame,
                goal:           this.project.goal,
                startDate:      this.project.startDate,
                endDate:        this.project.endDate,
                description:    this.project.description,
                outletIds,
                unitCodes
            });

            this.dispatchEvent(new ShowToastEvent({
                title:   'Pitch Project Created',
                message: 'Your new pitch project has been saved.',
                variant: 'success'
            }));

            // Navigate to the new record, then finish the flow if inside one
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: projId, actionName: 'view' }
            });
            this.dispatchEvent(new FlowNavigationFinishEvent());

        } catch (err) {
            this.saveError = err.body?.message || err.message || 'An unexpected error occurred.';
        } finally {
            this.isLoading = false;
        }
    }

    // ── private ───────────────────────────────────────────────────────────

    _validateCurrentStep() {
        if (this.currentStep === 1) {
            if (!this.project.name?.trim()) {
                this._toast('Validation', 'Project Name is required.', 'error');
                return false;
            }
            if (!this.project.ownerType) {
                this._toast('Validation', 'Owner Type is required.', 'error');
                return false;
            }
            if (!this.project.goal || this.project.goal <= 0) {
                this._toast('Validation', 'Goal must be a positive amount.', 'error');
                return false;
            }
        }
        return true;
    }

    _syncOutletRows() {
        const existingMap = new Map(this.outletUnitCodeRows.map(r => [r.outletId, r]));
        const outletMap = new Map(this.outlets.map(o => [o.Id, o.Name]));
        this.outletUnitCodeRows = this.selectedOutletIds.map(id => ({
            outletId:   id,
            outletName: outletMap.get(id) || id,
            unitCodes:  existingMap.has(id) ? existingMap.get(id).unitCodes : ''
        }));
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
