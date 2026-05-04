import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getCategoryTree from '@salesforce/apex/CategoryService.getCategoryTree';
import reparentCategory from '@salesforce/apex/CategoryService.reparentCategory';

const INDENT_PX = 20;

export default class CategoryTreeManager extends LightningElement {
    @track flatNodes = [];
    @track isLoading = true;
    @track errorMessage;

    _wiredResult;
    _dragSourceId;
    _expandedIds = new Set();

    @wire(getCategoryTree)
    wiredCategories(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.errorMessage = undefined;
            this._buildFlatNodes(result.data);
        } else if (result.error) {
            this.errorMessage = result.error.body?.message ?? 'Failed to load categories.';
        }
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get hasNodes() {
        return !this.isLoading && !this.hasError && this.flatNodes.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.hasError && this.flatNodes.length === 0;
    }

    _buildFlatNodes(categories) {
        // Build a map and tree structure
        const nodeMap = {};
        categories.forEach(cat => {
            nodeMap[cat.Id] = {
                ...cat,
                children: [],
                expanded: this._expandedIds.size === 0 ? true : this._expandedIds.has(cat.Id)
            };
        });

        const roots = [];
        categories.forEach(cat => {
            if (cat.Parent_Category__c) {
                const parent = nodeMap[cat.Parent_Category__c];
                if (parent) {
                    parent.children.push(nodeMap[cat.Id]);
                } else {
                    roots.push(nodeMap[cat.Id]);
                }
            } else {
                roots.push(nodeMap[cat.Id]);
            }
        });

        // Sort by Sort_Order__c then Name at each level
        const sort = nodes => {
            nodes.sort((a, b) => {
                const od = (a.Sort_Order__c ?? 999999) - (b.Sort_Order__c ?? 999999);
                return od !== 0 ? od : (a.Name ?? '').localeCompare(b.Name ?? '');
            });
            nodes.forEach(n => sort(n.children));
        };
        sort(roots);

        // Flatten with depth for CSS indentation
        const flat = [];
        const flatten = (nodes, depth) => {
            nodes.forEach(node => {
                flat.push({
                    Id: node.Id,
                    Name: node.Name,
                    Is_Active__c: node.Is_Active__c,
                    Parent_Category__c: node.Parent_Category__c,
                    Sort_Order__c: node.Sort_Order__c,
                    hasChildren: node.children.length > 0,
                    expanded: node.expanded,
                    isInactive: node.Is_Active__c === false,
                    expandIcon: node.expanded ? 'utility:chevrondown' : 'utility:chevronright',
                    indentStyle: `padding-left: ${depth * INDENT_PX + 4}px`,
                    rowClass: [
                        'tree-node',
                        'slds-p-vertical_xx-small',
                        node.Is_Active__c === false ? 'inactive-node' : ''
                    ].join(' ').trim()
                });
                if (node.expanded) flatten(node.children, depth + 1);
            });
        };
        flatten(roots, 0);
        this.flatNodes = flat;
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        if (this._expandedIds.has(id)) {
            this._expandedIds.delete(id);
        } else {
            this._expandedIds.add(id);
        }
        // Re-build from cached wire data
        if (this._wiredResult?.data) {
            this._buildFlatNodes(this._wiredResult.data);
        }
    }

    // ── Drag-and-drop ────────────────────────────────────────────────────────

    handleDragStart(event) {
        this._dragSourceId = event.currentTarget.dataset.id;
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', this._dragSourceId);
        event.currentTarget.classList.add('dragging');
    }

    handleDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
    }

    handleDragEnter(event) {
        const row = event.target.closest('[data-id]');
        if (row) row.classList.add('drag-over');
    }

    handleDragLeave(event) {
        const row = event.target.closest('[data-id]');
        if (row) row.classList.remove('drag-over');
    }

    handleDrop(event) {
        event.preventDefault();
        this._clearDragStyles();

        const targetRow = event.target.closest('[data-id]');
        if (!targetRow) return;

        const targetId = targetRow.dataset.id;
        const sourceId = this._dragSourceId;
        this._dragSourceId = null;

        if (!sourceId || sourceId === targetId) return;

        // Client-side cycle guard (server also validates)
        if (this._isDescendantOf(sourceId, targetId)) {
            this._toast('Error', 'Cannot move a category to one of its own descendants.', 'error');
            return;
        }

        this.isLoading = true;
        reparentCategory({ categoryId: sourceId, newParentId: targetId })
            .then(() => {
                this._toast('Success', 'Category moved successfully.', 'success');
                return refreshApex(this._wiredResult);
            })
            .catch(err => {
                this._toast('Error', err.body?.message ?? 'Failed to move category.', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    _isDescendantOf(ancestorId, nodeId) {
        // Walk up the flat node parent chain from nodeId
        const parentMap = {};
        (this._wiredResult?.data ?? []).forEach(n => {
            if (n.Parent_Category__c) parentMap[n.Id] = n.Parent_Category__c;
        });

        const visited = new Set();
        let current = nodeId;
        while (current && !visited.has(current)) {
            if (current === ancestorId) return true;
            visited.add(current);
            current = parentMap[current];
        }
        return false;
    }

    _clearDragStyles() {
        this.template.querySelectorAll('.drag-over').forEach(el => el.classList.remove('drag-over'));
        this.template.querySelectorAll('.dragging').forEach(el => el.classList.remove('dragging'));
    }

    // ── Action dispatchers ───────────────────────────────────────────────────

    handleAddRoot() {
        this.dispatchEvent(new CustomEvent('addcategory', { detail: { parentId: null } }));
    }

    handleAddChild(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('addcategory', {
            detail: { parentId: event.currentTarget.dataset.id }
        }));
    }

    handleRetire(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('retirecategory', {
            detail: { categoryId: event.currentTarget.dataset.id }
        }));
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
