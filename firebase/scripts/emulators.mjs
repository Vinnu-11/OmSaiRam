import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn, spawnSync } from 'node:child_process';
import { localConfig, projectId } from './local-config.mjs';

localConfig();
const action = process.argv[2];
if (!['start', 'test'].includes(action)) throw new Error('Expected start or test.');
const env = { ...process.env };
// The user-local runtime installed for this setup does not alter Android's
// Java/Gradle configuration or require machine-wide package installation.
const localJava = join(homedir(), '.local/share/om-sai-ram-java21');
if (!env.JAVA_HOME && existsSync(join(localJava, 'bin/java'))) {
    env.JAVA_HOME = localJava;
}
if (env.JAVA_HOME) env.PATH = `${join(env.JAVA_HOME, 'bin')}${process.platform === 'win32' ? ';' : ':'}${env.PATH}`;
const check = spawnSync('java', ['-version'], { env, encoding: 'utf8' });
const version = `${check.stderr || ''}${check.stdout || ''}`.match(/version "(\d+)/);
if (check.status !== 0 || !version || Number(version[1]) < 21) {
    throw new Error('Firebase emulators require Java 21+. Set JAVA_HOME to a compatible runtime.');
}
const cli = fileURLToPath(new URL('../node_modules/firebase-tools/lib/bin/firebase.js', import.meta.url));
const args = [
    cli, action === 'start' ? 'emulators:start' : 'emulators:exec',
    '--config', '../firebase.json', '--project', projectId, '--only', 'auth,firestore',
];
if (action === 'test') args.push('node --test --test-concurrency=1 tests/*.test.mjs');
const child = spawn(process.execPath, args, {
    cwd: fileURLToPath(new URL('..', import.meta.url)), env, stdio: 'inherit',
});
for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => { child.kill(signal); });
}
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('exit', (code, signal) => { process.exitCode = code ?? (signal ? 1 : 0); });