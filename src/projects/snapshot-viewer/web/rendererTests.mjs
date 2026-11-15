import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import vm from 'node:vm';

const renderer = await build({ entryPoints: [new URL('renderer.ts', import.meta.url).pathname], bundle: true, platform: 'node', format: 'cjs', write: false });
const context = vm.createContext({ exports: {}, module: { exports: {} } });
vm.runInContext(renderer.outputFiles[0].text, context);
const render = (markdown, images = {}) => context.module.exports.renderSnapshot({ markdown, images });

test('renders snapshot headings, window metadata, tables and screenshot controls', () => {
    const html = render('# Project snapshot\n\n## Windows\n\n- **App:** Finder\n\n| Window | State |\n| --- | --- |\n| Home | Left open |\n\n![Home](screenshots/window-1.png)', { 'screenshots/window-1.png': 'file:///archive/screenshots/window-1.png' });
    assert.match(html, /<h1>Project snapshot<\/h1>/);
    assert.match(html, /<strong>App:<\/strong> Finder/);
    assert.match(html, /<table>/);
    assert.match(html, /<button type="button" class="screenshot" aria-label="Enlarge Home">/);
    assert.match(html, /<img src="file:\/\/\/archive\/screenshots\/window-1.png" alt="Home">/);
});

test('renders raw HTML, scripts and iframes as inert text', () => {
    const html = render('<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n\n<iframe src="https://example.com"></iframe>');
    assert.doesNotMatch(html, /<(script|img|iframe)\b/);
    assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
});

test('only HTTP and HTTPS links are clickable', () => {
    const html = render('[Secure](https://example.com/a?b=1&c=2) [HTTP](http://example.com) [Local](notes.md) [Mail](mailto:user@example.com) [Protocol-relative](//example.com) [App](vscode://file/test)');
    assert.equal((html.match(/<a /g) || []).length, 2);
    assert.match(html, /href="https:\/\/example.com\/a\?b=1&amp;c=2"/);
    assert.equal((html.match(/class="unavailable-link"/g) || []).length, 4);
    assert.doesNotMatch(html, /href="(?:notes|mailto|\/\/|vscode)/);
});

test('unsafe and entity-obfuscated URL schemes cannot create navigation', () => {
    const html = render('[Script](javascript:alert%281%29) [Encoded](jav&#x61;script:alert%281%29) [Data](data:text/html,test) [VB](vbscript:test)');
    assert.doesNotMatch(html, /<a /);
});

test('only native-approved images can render', () => {
    const html = render('![Remote](https://example.com/a.png) ![Local](../private.png) ![Absent](screenshots/missing.png) ![Data](data:image/png;base64,aGVsbG8=)');
    assert.doesNotMatch(html, /<img /);
    assert.equal((html.match(/class="missing-image"/g) || []).length, 4);
});

test('a mapped URL must still be a local file URL without an authority', () => {
    for (const mapped of ['https://example.com/a.png', 'javascript:alert(1)', 'file://host/a.png', 'file:///a\n.png', 'data:image/png;base64,aGVsbG8=']) {
        assert.doesNotMatch(render('![Image](screenshots/window.png)', { 'screenshots/window.png': mapped }), /<img /);
    }
});

test('decodes percent-encoded image names exactly once', () => {
    const images = { 'screenshots/window 1.png': 'file:///archive/screenshots/window%201.png', 'screenshots/%20.png': 'file:///archive/screenshots/%2520.png' };
    assert.match(render('![Space](screenshots/window%201.png)', images), /src="file:\/\/\/archive\/screenshots\/window%201.png"/);
    assert.match(render('![Literal percent](screenshots/%2520.png)', images), /src="file:\/\/\/archive\/screenshots\/%2520.png"/);
    assert.doesNotMatch(render('![Malformed](screenshots/%FF.png)', images), /<img /);
});

test('prototype properties cannot approve image sources', () => {
    const images = Object.create({ 'screenshots/window.png': 'file:///private.png' });
    assert.doesNotMatch(render('![Image](screenshots/window.png)', images), /<img /);
});

test('image captions and native paths cannot escape HTML attributes', () => {
    const html = render('![&quot; onerror=&quot;alert(1)](screenshots/window.png)', { 'screenshots/window.png': 'file:///archive/a" onerror="evil.png' });
    assert.match(html, /alt="&quot; onerror=&quot;alert\(1\)"/);
    assert.match(html, /src="file:\/\/\/archive\/a&quot; onerror=&quot;evil.png"/);
    assert.doesNotMatch(html, /src="[^"]*" onerror=/);
});

test('malformed payloads fail clearly', () => {
    for (const data of [null, {}, { markdown: 2, images: {} }, { markdown: '# title' }]) {
        assert.throws(() => context.module.exports.renderSnapshot(data), /could not be read/);
    }
});

const html = await readFile(new URL('dist/viewer.html', import.meta.url), 'utf8');
const executable = html.match(/<script>([\s\S]*?)<\/script>/)[1];

test('generated template permits only its exact bundled script and local image loads', () => {
    const hash = createHash('sha256').update(executable).digest('base64');
    assert.ok(html.includes(`script-src 'sha256-${hash}'`));
    assert.match(html, /default-src 'none'/);
    assert.match(html, /img-src file:/);
    assert.match(html, /connect-src 'none'/);
    assert.equal(html.split('__SNAPSHOT_DATA__').length, 2);
    assert.doesNotMatch(html, /<(script|link|img)[^>]+(?:src|href)="https?:/);
});

function runBundle(data) {
    const nodes = {};
    const messages = [];
    const getNode = id => nodes[id] || (nodes[id] = {
        hidden: true, textContent: '', innerHTML: '', attributes: {},
        classList: { add() {}, remove() {} },
        setAttribute(key, value) { this.attributes[key] = value; },
        removeAttribute() {}, addEventListener() {}, querySelectorAll() { return []; },
    });
    getNode('snapshot-data').textContent = data;
    const legacy = vm.createContext({
        document: { getElementById: getNode, documentElement: getNode('root'), body: getNode('body'), addEventListener() {} },
        window: { webkit: { messageHandlers: { snapshotViewer: { postMessage: message => messages.push(message) } } } },
    });
    vm.runInContext('Object.entries = Object.values = Object.fromEntries = Object.hasOwn = undefined; Array.prototype.flat = Array.prototype.flatMap = Array.prototype.at = undefined; String.prototype.replaceAll = String.prototype.matchAll = undefined; globalThis = undefined;', legacy);
    vm.runInContext(executable, legacy);
    return { nodes, messages };
}

test('actual Safari-targeted bundle renders without newer JavaScript builtin APIs', () => {
    const { nodes, messages } = runBundle(JSON.stringify({ markdown: '# Snapshot 😀\n\n**Finder** &amp; Safari\n\n![Home](screenshots/window.png)', images: { 'screenshots/window.png': 'file:///archive/window.png' } }));
    assert.match(nodes.snapshot.innerHTML, /<h1>Snapshot 😀<\/h1>/);
    assert.match(nodes.snapshot.innerHTML, /<img /);
    assert.equal(nodes.root.attributes['data-viewer-state'], 'ready');
    assert.equal(messages.length, 1);
    assert.equal(messages[0].type, 'ready');
});

test('actual bundle reports a readable error for invalid snapshot JSON', () => {
    const { nodes, messages } = runBundle('{broken');
    assert.equal(nodes.root.attributes['data-viewer-state'], 'error');
    assert.match(nodes.snapshot.textContent, /Open Externally/);
    assert.equal(messages.length, 1);
    assert.equal(messages[0].type, 'error');
});
