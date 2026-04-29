import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getBatchStats from '@salesforce/apex/IngestController.getBatchStats';
import getActiveSources from '@salesforce/apex/IngestController.getActiveSources';
import launchBatch from '@salesforce/apex/IngestController.launchBatch';

const STATUS_CONFIG = {
    Pending:   { icon: 'utility:clock', css: 'slds-badge slds-badge_lightest' },
    Excluded:  { icon: 'utility:ban', css: 'slds-badge slds-theme_warning' },
    Error:     { icon: 'utility:error', css: 'slds-badge slds-theme_error' },
    Matched:   { icon: 'utility:check', css: 'slds-badge slds-theme_success' },
    Unmatched: { icon: 'utility:question', css: 'slds-badge slds-theme_warning' }
};

export default class LoadBatchDashboard extends LightningElement {
    @track sourceBlocks = [];
    @track isLoading = false;

    _wiredStatsResult;
    _sourceSystems = [];

    @wire(getActiveSources)
    wiredSources({ data }) {
        if (data) this._sourceSystems = data;
    }

    @wire(getBatchStats)
    wiredStats(result) {
        this._wiredStatsResult = result;
        if (result.data) {
            this.sourceBlocks = this.buildBlocks(result.data);
        } else if (result.error) {
            this.showToast('Error loading stats', result.error.body?.message, 'error');
        }
    }

    get hasStats() {
        return this.sourceBlocks?.length > 0;
    }

    buildBlocks(stats) {
        // Group by sourceName
        const map = new Map();
        for (const stat of stats) {
            const name = stat.sourceName ?? '(unknown)';
            if (!map.has(name)) map.set(name, []);
            const cfg = STATUS_CONFIG[stat.status] ?? { icon: 'utility:info', css: 'slds-badge slds-badge_lightest' };
            map.get(name).push({
                status: stat.status,
                rowCount: stat.rowCount,
                pillClass: cfg.css,
                icon: cfg.icon
            });
        }

        return Array.from(map.entries()).map(([name, stats]) => {
            const src = this._sourceSystems.find(s => s.Name === name);
            return { sourceName: name, stats, sourceId: src?.Id };
        });
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await refreshApex(this._wiredStatsResult);
        } finally {
            this.isLoading = false;
        }
    }

    async handleRunBatch(event) {
        const sourceId = event.currentTarget.dataset.source;
        if (!sourceId) {
            this.showToast('Cannot launch', 'No Source System ID available for this tile.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            const jobId = await launchBatch({ sourceSystemId: sourceId });
            this.showToast('Batch launched', 'Job ID: ' + jobId, 'success');
            await refreshApex(this._wiredStatsResult);
        } catch (error) {
            this.showToast('Batch failed to launch', error.body?.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message: message ?? '', variant }));
    }
}
