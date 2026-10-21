import { renderSnapshot, SnapshotData } from './renderer';

interface ViewerWindow extends Window {
    webkit?: { messageHandlers?: { snapshotViewer?: { postMessage: (message: object) => void } } };
}

function notify(message: object): void {
    const handler = (window as ViewerWindow).webkit?.messageHandlers?.snapshotViewer;
    if (handler) handler.postMessage(message);
}

function installZoom(article: HTMLElement): void {
    const overlay = document.getElementById('image-zoom')!;
    const enlarged = document.getElementById('zoom-image') as HTMLImageElement;
    const caption = document.getElementById('zoom-caption')!;
    const close = document.getElementById('zoom-close') as HTMLButtonElement;
    let previousFocus: HTMLElement | null = null;
    const dismiss = (): void => {
        overlay.hidden = true;
        article.removeAttribute('aria-hidden');
        enlarged.removeAttribute('src');
        document.body.classList.remove('zoom-open');
        if (previousFocus) previousFocus.focus();
    };
    article.addEventListener('click', event => {
        const target = event.target as HTMLElement;
        const button = target.closest('button.screenshot') as HTMLButtonElement | null;
        const image = button?.querySelector('img');
        if (!button || !image) return;
        event.preventDefault();
        previousFocus = button;
        enlarged.src = image.src;
        enlarged.alt = image.alt;
        caption.textContent = image.alt;
        overlay.hidden = false;
        article.setAttribute('aria-hidden', 'true');
        document.body.classList.add('zoom-open');
        close.focus();
    });
    close.addEventListener('click', dismiss);
    overlay.addEventListener('click', event => {
        if (event.target === overlay) dismiss();
    });
    document.addEventListener('keydown', event => {
        if (overlay.hidden) return;
        if (event.key === 'Escape' || event.key === 'Esc') {
            event.preventDefault();
            event.stopPropagation();
            dismiss();
        } else if (event.key === 'Tab') {
            event.preventDefault();
            close.focus();
        }
    });
}

function installImageFallbacks(article: HTMLElement): void {
    const images = article.querySelectorAll('button.screenshot img');
    for (let index = 0; index < images.length; index++) {
        const image = images[index] as HTMLImageElement;
        image.addEventListener('error', () => {
            const button = image.parentElement;
            if (!button?.parentElement) return;
            const placeholder = document.createElement('span');
            placeholder.className = 'missing-image';
            placeholder.setAttribute('role', 'note');
            placeholder.textContent = `Screenshot unavailable: ${image.alt}`;
            button.parentElement.replaceChild(placeholder, button);
        });
    }
}

function showSnapshot(): void {
    const article = document.getElementById('snapshot')!;
    try {
        const data = JSON.parse(document.getElementById('snapshot-data')!.textContent || '') as SnapshotData;
        article.innerHTML = renderSnapshot(data);
        if (!article.textContent?.trim()) article.textContent = 'This snapshot is empty.';
        installImageFallbacks(article);
        installZoom(article);
        document.documentElement.setAttribute('data-viewer-state', 'ready');
        notify({ type: 'ready' });
    } catch (error) {
        const message = error instanceof Error ? error.message : 'This snapshot could not be displayed.';
        article.textContent = 'This snapshot could not be displayed. Use Open Externally to view the original Markdown.';
        article.classList.add('render-error');
        document.documentElement.setAttribute('data-viewer-state', 'error');
        notify({ type: 'error', message });
    }
}

showSnapshot();
