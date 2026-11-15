import { build, transform } from 'esbuild';
import ts from 'typescript';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const web = resolve(root, 'src/projects/snapshot-viewer/web');
const check = process.argv.includes('--check');
const result = await build({
    absWorkingDir: root,
    entryPoints: [resolve(web, 'viewer.ts')],
    bundle: true,
    write: false,
    format: 'iife',
    platform: 'browser',
    target: 'es2015',
    minify: false,
    charset: 'ascii',
    legalComments: 'none',
    logOverride: { 'unsupported-regexp': 'error' },
});
// Safari 10 has block-scoping bugs; esbuild cannot lower let/const. TypeScript lowers
// the entire bundle to ES5 before esbuild checks the final Safari 10 syntax target.
const compatible = ts.transpileModule(result.outputFiles[0].text, {
    compilerOptions: { target: ts.ScriptTarget.ES5, downlevelIteration: true, removeComments: true },
}).outputText;
const javascript = (await transform(compatible, {
    target: 'safari10', minify: true, charset: 'ascii', logOverride: { 'unsupported-regexp': 'error' },
})).code.replace(/<\/script/gi, '<\\/script');
const css = (await transform(await readFile(resolve(web, 'viewer.css'), 'utf8'), { loader: 'css', target: 'safari10', minify: true })).code;
const hash = `sha256-${createHash('sha256').update(javascript).digest('base64')}`;
const html = (await readFile(resolve(web, 'template.html'), 'utf8'))
    .replace('__SCRIPT_HASH__', () => hash)
    .replace('__VIEWER_CSS__', () => css)
    .replace('__VIEWER_JS__', () => javascript);
const licenses = [
    ['markdown-it', 'LICENSE'],
    ['entities', 'LICENSE'],
    ['linkify-it', 'LICENSE'],
    ['mdurl', 'LICENSE'],
    ['punycode.js', 'LICENSE-MIT.txt'],
    ['uc.micro', 'LICENSE.txt'],
];
let notices = 'Snapshot Viewer — third-party notices\n\n';
for (const [name, license] of licenses) {
    const directory = resolve(root, 'node_modules', name);
    const info = JSON.parse(await readFile(resolve(directory, 'package.json'), 'utf8'));
    notices += `${name} ${info.version}\n${'='.repeat(64)}\n${await readFile(resolve(directory, license), 'utf8')}\n\n`;
}
await mkdir(resolve(web, 'dist'), { recursive: true });
for (const [name, content] of [['viewer.html', html], ['THIRD-PARTY-NOTICES.txt', notices.trimEnd() + '\n']]) {
    const path = resolve(web, 'dist', name);
    if (check) {
        if (await readFile(path, 'utf8').catch(() => '') !== content) throw new Error(`${name} is stale; run npm run viewer:build`);
    } else {
        await writeFile(path, content);
    }
}
async function sourceFiles(directory) {
    const files = [];
    for (const entry of await readdir(directory, { withFileTypes: true })) {
        if (entry.name === 'dist' || entry.name === '.DS_Store') continue;
        const path = resolve(directory, entry.name);
        if (entry.isDirectory()) files.push(...await sourceFiles(path));
        else if (entry.isFile()) files.push(relative(root, path));
    }
    return files;
}
const files = (await sourceFiles(web)).concat([
    'scripts/build-snapshot-viewer.mjs', 'scripts/check-snapshot-viewer.sh', 'package.json', 'package-lock.json',
    'src/projects/snapshot-viewer/web/dist/viewer.html', 'src/projects/snapshot-viewer/web/dist/THIRD-PARTY-NOTICES.txt',
]).sort();
const manifest = (await Promise.all(files.map(async path => `${createHash('sha256').update(await readFile(resolve(root, path))).digest('hex')}  ${path}\n`))).join('');
const manifestPath = resolve(web, 'dist/sources.sha256');
if (check) {
    if (await readFile(manifestPath, 'utf8').catch(() => '') !== manifest) throw new Error('Viewer source manifest is stale; run npm run viewer:build');
} else {
    await writeFile(manifestPath, manifest);
}
console.log(`Snapshot viewer ${check ? 'verified' : 'built'} (${Buffer.byteLength(html)} bytes, Safari 10 target).`);
