import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin }              from 'lightning/navigation';
import { FlowNavigationFinishEvent }    from 'lightning/flowSupport';
import getActiveOutlets                 from '@salesforce/apex/PitchProjectController.getActiveOutlets';
import saveProject                      from '@salesforce/apex/PitchProjectController.saveProject';

const STEP_LABELS = {
    1 : 'Basic Info',
    2 : 'Participating Outlets',
    3 : 'Unit Codes',
    4 : 'Confirm & Create'
};

export default class PitchProjectCreator extends NavigationMixin(LightningElement) {

    @api recordId;

    // ── State ─────────────────────────────────────────────────────────────

    @track currentStep = 1;
    @track form = {
        projectName    : '',
        ownerType      : '',
        owningMarketId : null,
        timeFrame      : '',
        goal           : null,
        description    : '',
        startDate      : '',
        endDate        : ''
    };
    @track outletOptions  = [];   // { id, label, checked }
    @track validationError = '';
    @track saveError       = '';
    @track isSaving        = false;

    outletsLoading = false;
    outletsError   = false;

    // ── Wired outlets ─────────────────────────────────────────────────────

    @wire(getActiveOutlets)
    wiredOutlets({ error, data }) {
        if (data) {
            this.outletsLoading = false;
            this.outletOptions  = data.map(o => ({
                id      : o.Id,
                label   : o.Name,
                code    : o.Code__c,
                checked : false,
                unitCode: ''
            }));
        } else if (error) {
            this.outletsLoading = false;
            this.outletsError   = true;
            console.error('getActiveOutlets error', error);
        } else {
            this.outletsLoading = true;
        }
    }

    // ── Computed ──────────────────────────────────────────────────────────

    get currentStepStr() { return String(this.currentStep); }
    get stepLabel()       { return STEP_LABELS[this.currentStep]; }

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }

    get isLastStep() { return this.currentStep === 4; }
    get showBack()   { return this.currentStep > 1; }

    get isMarketOwner() { return this.form.ownerType === 'Market'; }

    get ownerTypeOptions() {
        return [
            { label: 'Corporate', value: 'Corporate' },
            { label: 'Market',    value: 'Market' }
        ];
    }

    get hasOutlets() {
        return !this.outletsLoading && !this.outletsError && this.outletOptions.length > 0;
    }

    get selectedOutlets() {
        return this.outletOptions.filter(o => o.checked);
    }

    get selectedCount() { return this.selectedOutlets.length; }

    get formattedGoal() {
        if (!this.form.goal) return '$0';
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 })
            .format(this.form.goal);
    }

    // ── Event handlers ────────────────────────────────────────────────────

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.form   = { ...this.form, [field]: event.target.value };
        this.validationError = '';
    }

    handleMarketChange(event) {
        this.form = { ...this.form, owningMarketId: event.detail.recordId };
    }

    handleOutletToggle(event) {
        const outletId = event.target.dataset.id;
        this.outletOptions = this.outletOptions.map(o =>
            o.id === outletId ? { ...o, checked: event.target.checked } : o
        );
        this.validationError = '';
    }

    handleUnitCodeChange(event) {
        const outletId = event.target.dataset.id;
        this.outletOptions = this.outletOptions.map(o =>
            o.id === outletId ? { ...o, unitCode: event.target.value } : o
        );
        this.validationError = '';
    }

    handleNext() {
        const err = this.validateCurrentStep();
        if (err) {
            this.validationError = err;
            return;
        }
        this.validationError = '';
        this.currentStep++;
    }

    handleBack() {
        this.validationError = '';
        this.saveError = '';
        this.currentStep--;
    }

    async handleSubmit() {
        this.saveError  = '';
        this.isSaving   = true;

        const outletsPayload = this.selectedOutlets.map(o => ({
            outletId : o.id,
            unitCode : o.unitCode
        }));

        try {
            const newId = await saveProject({
                projectName    : this.form.projectName,
                ownerType      : this.form.ownerType,
                owningMarketId : this.form.owningMarketId || null,
                timeFrame      : this.form.timeFrame,
                goal           : this.form.goal ? Number(this.form.goal) : 0,
                description    : this.form.description,
                startDate      : this.form.startDate   || null,
                endDate        : this.form.endDate     || null,
                outlets        : outletsPayload
            });

            // Navigate to the new record
            this[NavigationMixin.Navigate]({
                type       : 'standard__recordPage',
                attributes : {
                    recordId   : newId,
                    objectApiName : 'Pitch_Project__c',
                    actionName : 'view'
                }
            });

            // Finish the flow modal (if used inside a Screen Flow)
            this.dispatchEvent(new FlowNavigationFinishEvent());

        } catch (err) {
            this.saveError = err.body ? err.body.message : String(err);
        } finally {
            this.isSaving = false;
        }
    }

    // ── Validation ────────────────────────────────────────────────────────

    validateCurrentStep() {
        switch (this.currentStep) {
            case 1: {
                if (!this.form.projectName || !this.form.projectName.trim()) {
                    return 'Project Name is required.';
                }
                if (!this.form.ownerType) {
                    return 'Owner Type is required.';
                }
                if (!this.form.goal || Number(this.form.goal) <= 0) {
                    return 'Goal must be a positive number.';
                }
                break;
            }
            case 2: {
                if (this.selectedCount === 0) {
                    return 'Select at least one participating outlet.';
                }
                break;
            }
            case 3: {
                const missing = this.selectedOutlets.filter(o => !o.unitCode || !o.unitCode.trim());
                if (missing.length > 0) {
                    return `Enter a unit code for: ${missing.map(o => o.label).join(', ')}`;
                }
                break;
            }
            default:
                break;
        }
        return null;
    }
}
