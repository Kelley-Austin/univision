import { LightningElement, track } from 'lwc';

export default class SalesOpsConsole extends LightningElement {
    @track activeTab = 'load-batches';

    handleTabChange(e) {
        this.activeTab = e.detail.value;
    }
}
