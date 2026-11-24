import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { localConfig, localFunctionsConfig, localFunctionsEnvironment, projectId } from '../scripts/local-config.mjs';

test('local configuration uses only the demo project and loopback endpoints', () => {
    assert.deepEqual(localConfig({}), {
        projectId,
        auth: { host: '127.0.0.1', port: 9099 },
        firestore: { host: '127.0.0.1', port: 8085 },
    });
});

for (const name of ['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT']) {
    test(`rejects live project through ${name}`, () => {
        assert.throws(() => localConfig({ [name]: 'production-project' }), /must be demo-/);
    });
}
for (const name of ['FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST']) {
    test(`rejects remote or unexpected endpoints through ${name}`, () => {
        assert.throws(() => localConfig({ [name]: 'example.com:443' }), /remote endpoints are refused/);
    });
}

test('separate Functions configuration preserves existing Auth/Firestore ports and isolates hub/logging', () => {
    assert.deepEqual(localFunctionsConfig({}), {
        projectId,
        functions: { host: '127.0.0.1', port: 5001 }, hub: { host: '127.0.0.1', port: 4401 },
        logging: { host: '127.0.0.1', port: 4501 }
    });
    assert.equal(localConfig({}).firestore.port, 8085);
});
for (const env of [{ GCLOUD_PROJECT: 'live' }, { GCP_PROJECT: 'live' },
{ GOOGLE_APPLICATION_CREDENTIALS: '/private/key.json' }, { FIREBASE_TOKEN: 'fixture-not-a-secret' },
{ google_application_credentials: '/private/fixture.json' }, { WEB_HOST: 'remote.example.test' }]) {
    test(`Functions launcher rejects credentials/project ${JSON.stringify(env)}`, () => assert.throws(() => localFunctionsConfig(env)));
}
for (const service of ['functions', 'hub', 'logging']) {
    for (const change of [{ host: '0.0.0.0' }, { port: 8085 }]) {
        test(`Functions launcher rejects unsafe/conflicting ${service} ${JSON.stringify(change)}`, () => {
            const config = JSON.parse(readFileSync(new URL('../functions-emulator.json', import.meta.url), 'utf8'));
            Object.assign(config.emulators[service], change); assert.throws(() => localFunctionsConfig({}, config));
        });
    }
}
test('separate launcher cannot start Auth/Firestore, enable UI or change runtime/source', () => {
    for (const mutate of [config => { config.emulators.auth = { host: '127.0.0.1', port: 9099 }; },
    config => { config.emulators.firestore = { host: '127.0.0.1', port: 8085 }; },
    config => { config.emulators.ui.enabled = true; }, config => { config.functions.runtime = 'nodejs24'; },
    config => { config.functions.source = '../backend'; }]) {
        const config = JSON.parse(readFileSync(new URL('../functions-emulator.json', import.meta.url), 'utf8'));
        mutate(config); assert.throws(() => localFunctionsConfig({}, config));
    }
});
test('Functions child isolates ambient ADC/CLI configuration without changing caller environment', () => {
    const parent = { HOME: '/original/home', XDG_CONFIG_HOME: '/original/config', CLOUDSDK_CONFIG: '/original/gcloud', PATH: '/bin' };
    const child = localFunctionsEnvironment(parent, '/tmp/functions-fixture');
    assert.equal(child.HOME, '/tmp/functions-fixture'); assert.equal(child.XDG_CONFIG_HOME, '/tmp/functions-fixture/.config');
    assert.equal(child.CLOUDSDK_CONFIG, '/tmp/functions-fixture/gcloud'); assert.equal(child.GCLOUD_PROJECT, projectId);
    assert.equal(child.METADATA_SERVER_DETECTION, 'none');
    assert.equal(child.GCE_METADATA_HOST, '127.0.0.1:1'); assert.equal(child.GCE_METADATA_IP, '127.0.0.1:1');
    assert.equal(parent.HOME, '/original/home'); assert.equal(child.PATH, '/bin');
});
test('isolated Google auth cannot acquire cached or compute-metadata credentials', () => {
    const home = mkdtempSync(join(tmpdir(), 'om-sai-ram-credential-test-'));
    try {
        const authModule = createRequire(import.meta.url).resolve('google-auth-library');
        const child = spawnSync(process.execPath, ['-e',
            'const {GoogleAuth}=require(process.argv[1]); new GoogleAuth().getAccessToken().then(()=>{process.exitCode=1},()=>console.log("Credential acquisition blocked"));',
            authModule], { env: localFunctionsEnvironment(process.env, home), encoding: 'utf8', timeout: 10000 });
        assert.equal(child.status, 0, 'Credential isolation check must complete without obtaining a token.');
        assert.equal(child.stdout.trim(), 'Credential acquisition blocked');
    } finally { rmSync(home, { recursive: true, force: true }); }
});