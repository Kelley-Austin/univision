import { LightningElement, wire, track } from 'lwc';
import getKpiData from '@salesforce/apex/MdmKpiController.getKpiData';

export default class MdmKpiTiles extends LightningElement {
    @track kpiTiles = [];
    @track isLoading = true;
    @track errorMessage;

    @wire(getKpiData)
    wiredKpis({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.errorMessage = undefined;
            this.kpiTiles = this._buildTiles(data);
        } else if (error) {
            this.errorMessage = error.body?.message ?? 'Failed to load KPI data.';
        }
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get hasData() {
        return !this.isLoading && !this.hasError;
    }

    _buildTiles(d) {
        return [
            {
                id: 'holdco',
                label: 'HoldCo Accounts',
                value: d.holdCoCount,
                icon: 'standard:account',
                iconVariant: 'default',
                cardClass: 'kpi-tile slds-box',
                alertMessage: null
            },
            {
                id: 'agency',
                label: 'Agency Accounts',
                value: d.agencyCount,
                icon: 'standard:account',
                iconVariant: 'default',
                cardClass: 'kpi-tile slds-box',
                alertMessage: null
            },
            {
                id: 'advertiser',
                label: 'Advertiser Accounts',
                value: d.advertiserCount,
                icon: 'standard:account',
                iconVariant: 'default',
                cardClass: 'kpi-tile slds-box',
                alertMessage: null
            },
            {
                id: 'orphans',
                label: 'Accounts Missing Parent',
                value: d.orphanCount,
                icon: 'utility:warning',
                iconVariant: d.orphanCount > 0 ? 'warning' : 'default',
                cardClass: `kpi-tile slds-box${d.orphanCount > 0 ? ' kpi-tile--alert' : ''}`,
                alertMessage: d.orphanCount > 0 ? 'Hierarchy gaps detected' : null
            },
            {
                id: 'categories',
                label: 'Active Categories',
                value: d.activeCategoryCount,
                icon: 'standard:hierarchy',
                iconVariant: 'default',
                cardClass: 'kpi-tile slds-box',
                alertMessage: null
            },
            {
                id: 'untagged',
                label: 'Accounts Without Category',
                value: d.untaggedAccountCount,
                icon: 'utility:error',
                iconVariant: d.untaggedAccountCount > 0 ? 'error' : 'default',
                cardClass: `kpi-tile slds-box${d.untaggedAccountCount > 0 ? ' kpi-tile--alert' : ''}`,
                alertMessage: d.untaggedAccountCount > 0 ? 'Assign via MDM triage' : null
            }
        ];
    }
}
