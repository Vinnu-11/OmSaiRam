import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { localFunctionsConfig, localFunctionsEnvironment, projectId } from './local-config.mjs';

const settings = localFunctionsConfig();
if (Number(process.versions.node.split('.')[0]) !== 22) {
    throw new Error('Use Node 22 for the pinned Functions runtime; no fallback to another runtime is allowed.');
}
if (!existsSync(new URL('../functions/node_modules/firebase-functions/package.json', import.meta.url))) {
    throw new Error('Install Functions dependencies first: npm --prefix firebase/functions ci --ignore-scripts.');
}
for (const { host, port } of [settings.functions, settings.hub, settings.logging]) {
    await new Promise((resolve, reject) => {
        const server = createServer();
        server.once('error', () => reject(new Error(`Local port ${port} is occupied; existing services will not be stopped.`)));
        server.listen(port, host, () => server.close(resolve));
    });
}
const cli = fileURLToPath(new URL('../node_modules/firebase-tools/lib/bin/firebase.js', import.meta.url));
const runtimeHome = mkdtempSync(join(tmpdir(), 'om-sai-ram-functions-'));
process.on('exit', () => rmSync(runtimeHome, { recursive: true, force: true }));
const child = spawn(process.execPath, [cli, 'emulators:start', '--config', 'functions-emulator.json',
    '--project', projectId, '--only', 'functions'], {
    cwd: fileURLToPath(new URL('..', import.meta.url)), env: localFunctionsEnvironment(process.env, runtimeHome), stdio: 'inherit',
});
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal));
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('exit', (code, signal) => { process.exitCode = code ?? (signal ? 1 : 0); });