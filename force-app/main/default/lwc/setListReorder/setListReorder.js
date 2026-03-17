import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getSetListSongs from '@salesforce/apex/SetListReorderController.getSetListSongs';
import updateOrdersOrdered from '@salesforce/apex/SetListReorderController.updateOrdersOrdered';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class SetListReorder extends LightningElement {
    @api setListId;   // optional
    @api recordId;    // injected automatically on Record Pages
    @track rows = [];
    loading = true;
    draggingIndex = null;
    wiredSongsResult;

    get effectiveSetListId() {
        return this.setListId || this.recordId;
    }

    @wire(getSetListSongs, { setListId: '$effectiveSetListId' })
    wiredSongs(result) {
        this.wiredSongsResult = result;
        const { data, error } = result;
        this.loading = false;
        if (error) {
            this.toast('Error', this.normalizeError(error), 'error');
            return;
        }
        if (data) {
            const sorted = [...data].sort((a, b) => Number(a.currentOrder || 0) - Number(b.currentOrder || 0));
            this.rows = sorted.map((s, idx) => ({
                id: s.id,
                name: s.name,
                currentOrder: Number(s.currentOrder || 0),
                newOrder: idx + 1
            }));
        }
    }
    // Drag & drop handlers
    onDragStart(evt) {
        const idx = Number(evt.currentTarget?.dataset?.index);
        this.draggingIndex = idx;
        evt.dataTransfer.dropEffect = 'move';
        evt.dataTransfer.setData('text/plain', String(idx)); // required for Firefox
        this._scrollContainer = this._getScrollContainer();
        this._boundDocDragOver = this._onDocumentDragOver.bind(this);
        document.addEventListener('dragover', this._boundDocDragOver);
    }

    onDragEnd() {
        this.draggingIndex = null;
        document.removeEventListener('dragover', this._boundDocDragOver);
        if (this._scrollInterval) {
            clearInterval(this._scrollInterval);
            this._scrollInterval = null;
        }
    }

    _getScrollContainer() {
        const own = this.template.querySelector('.list-scroll-container');
        if (own && own.scrollHeight > own.clientHeight) return own;
        let el = this.template.host;
        while (el && el !== document.body) {
            const style = getComputedStyle(el);
            const oy = style.overflowY;
            if ((oy === 'auto' || oy === 'scroll') && el.scrollHeight > el.clientHeight) {
                return el;
            }
            el = el.parentElement;
        }
        return document.scrollingElement || document.documentElement;
    }

    _onDocumentDragOver(evt) {
        const edgeSize = 80;
        const scrollSpeed = 12;
        if (this._scrollInterval) {
            clearInterval(this._scrollInterval);
            this._scrollInterval = null;
        }
        const container = this._scrollContainer;
        if (evt.clientY < edgeSize) {
            this._scrollInterval = setInterval(() => {
                if (container && container.scrollTop > 0) {
                    container.scrollTop = Math.max(0, container.scrollTop - scrollSpeed);
                }
                window.scrollBy(0, -scrollSpeed);
            }, 16);
        } else if (evt.clientY > window.innerHeight - edgeSize) {
            this._scrollInterval = setInterval(() => {
                if (container) {
                    const maxScroll = container.scrollHeight - container.clientHeight;
                    if (container.scrollTop < maxScroll) {
                        container.scrollTop = Math.min(maxScroll, container.scrollTop + scrollSpeed);
                    }
                }
                window.scrollBy(0, scrollSpeed);
            }, 16);
        }
    }

    onDragOver(evt) {
        evt.preventDefault(); // allow drop
        evt.dataTransfer.dropEffect = 'move';
    }

    onDrop(evt) {
        evt.preventDefault();
        const targetIndex = Number(evt.currentTarget?.dataset?.index);
        const sourceIndex = this.draggingIndex;
        this.onDragEnd();

        if (
            isNaN(sourceIndex) ||
            isNaN(targetIndex) ||
            sourceIndex === targetIndex ||
            sourceIndex < 0 ||
            targetIndex < 0
        ) {
            return;
        }

        const newRows = [...this.rows];
        const [moved] = newRows.splice(sourceIndex, 1);
        newRows.splice(targetIndex, 0, moved);

        this.rows = newRows.map((r, i) => ({ ...r, newOrder: i + 1 }));
    }

    async onSave() {
        if (!this.rows.length) return;
        try {
            this.loading = true;
            const orderedIds = this.rows.map(r => r.id);
            await updateOrdersOrdered({ orderedIds });
            this.rows = this.rows.map((r, i) => ({ ...r, currentOrder: i + 1, newOrder: i + 1 }));
            this.toast('Success', 'Order updated.', 'success');
            if (this.wiredSongsResult) {
                await refreshApex(this.wiredSongsResult);
            }
        } catch (e) {
            this.toast('Error', this.normalizeError(e), 'error');
        } finally {
            this.loading = false;
        }
    }

    // Utility
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    normalizeError(e) {
        try {
            if (Array.isArray(e.body)) return e.body.map(er => er.message).join(', ');
            if (typeof e.body?.message === 'string') return e.body.message;
            if (typeof e.message === 'string') return e.message;
        } catch (ignore) {}
        return 'Unknown error';
    }
}
