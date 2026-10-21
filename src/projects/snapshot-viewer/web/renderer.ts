import MarkdownIt from 'markdown-it';

export interface SnapshotData {
    markdown: string;
    images: Record<string, string>;
}

function isExternalLink(value: string): boolean {
    return /^https?:\/\/[^\s\\\u0000-\u001f\u007f]+$/i.test(value);
}

function imageSource(source: string, images: Record<string, string>): string | undefined {
    let decoded: string;
    try {
        decoded = decodeURIComponent(source);
    } catch {
        return undefined;
    }
    if (!Object.prototype.hasOwnProperty.call(images, decoded)) return undefined;
    const mapped = images[decoded];
    return typeof mapped === 'string' && /^file:\/\/\/[^\u0000-\u001f\u007f]*$/i.test(mapped) ? mapped : undefined;
}

export function renderSnapshot(data: SnapshotData): string {
    if (!data || typeof data.markdown !== 'string' || !data.images || typeof data.images !== 'object') {
        throw new Error('This snapshot could not be read.');
    }
    const markdown = new MarkdownIt({ html: false, linkify: false, typographer: false });
    markdown.renderer.rules.image = (tokens, index, options, _environment, renderer) => {
        const token = tokens[index];
        const alt = renderer.renderInlineAsText(token.children || [], options, {});
        const source = imageSource(String(token.attrGet('src') || ''), data.images);
        const escapedAlt = markdown.utils.escapeHtml(alt || 'Window screenshot');
        if (!source) return `<span class="missing-image" role="note">Screenshot unavailable${alt ? `: ${escapedAlt}` : ''}</span>`;
        return `<button type="button" class="screenshot" aria-label="Enlarge ${escapedAlt}"><img src="${markdown.utils.escapeHtml(source)}" alt="${escapedAlt}"><span class="screenshot-hint" aria-hidden="true">Click to enlarge</span></button>`;
    };
    markdown.core.ruler.after('inline', 'snapshot-links', state => {
        for (const block of state.tokens) {
            if (!block.children) continue;
            const tags: string[] = [];
            for (const token of block.children) {
                if (token.type === 'link_open') {
                    const external = isExternalLink(String(token.attrGet('href') || ''));
                    token.tag = external ? 'a' : 'span';
                    if (external) token.attrSet('rel', 'noreferrer noopener');
                    else token.attrs = [['class', 'unavailable-link'], ['title', 'Use Open Externally to follow this link']];
                    tags.push(token.tag);
                } else if (token.type === 'link_close') {
                    token.tag = tags.pop() || 'span';
                }
            }
        }
    });
    return markdown.render(data.markdown);
}
