import { readFileSync } from 'node:fs';
import { join } from 'node:path';

export const projectId = 'demo-om-sai-ram';
const config = JSON.parse(readFileSync(new URL('../../firebase.json', import.meta.url), 'utf8'));

// Restrict all fixtures/tests to the configured loopback emulators. Never let
// missing emulator configuration fall through to the live Firebase services.
export function localConfig(env = process.env) {
    for (const name of ['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT']) {
        if (env[name] && env[name] !== projectId) {
            throw new Error(`${name} must be ${projectId} for local scripts.`);
        }
    }
    if (!projectId.startsWith('demo-')) throw new Error('A demo project is required.');
    const result = { projectId };
    for (const [service, variable] of [
        ['auth', 'FIREBASE_AUTH_EMULATOR_HOST'],
        ['firestore', 'FIRESTORE_EMULATOR_HOST'],
    ]) {
        const { host, port } = config.emulators[service];
        if (host !== '127.0.0.1') throw new Error('Local scripts require loopback emulators.');
        const expected = `${host}:${port}`;
        if (env[variable] && env[variable] !== expected) {
            throw new Error(`${variable} must be ${expected}; remote endpoints are refused.`);
        }
        result[service] = { host, port };
    }
    return result;
}

export async function requireEmulators(settings = localConfig()) {
    for (const { host, port } of [settings.auth, settings.firestore]) {
        try {
            const response = await fetch(`http://${host}:${port}/`, {
                signal: AbortSignal.timeout(3000),
            });
            // Some emulator roots return 404, but a responding local service suffices;
            // SDK requests subsequently verify the service and project.
            await response.body?.cancel();
        } catch {
            throw new Error(`Emulator unavailable at ${host}:${port}. Start npm run emulators first.`);
        }
    }
}

export const firebaseOptions = {
    apiKey: 'demo-local-api-key',
    projectId,
    appId: '1:123456789:web:local-development',
};

const functionsConfig = JSON.parse(readFileSync(new URL('../functions-emulator.json', import.meta.url), 'utf8'));

export function localFunctionsConfig(env = process.env, selected = functionsConfig) {
    localConfig(env);
    if (env.GOOGLE_APPLICATION_CREDENTIALS || env.google_application_credentials || env.FIREBASE_TOKEN || env.WEB_HOST ||
        (env.GCP_PROJECT && env.GCP_PROJECT !== projectId)) {
        throw new Error('Functions require the local demo project without credentials or remote host overrides.');
    }
    if (selected.functions?.source !== 'functions' || selected.functions?.codebase !== 'public-feeds' ||
        selected.functions?.runtime !== 'nodejs22' || config.functions?.source !== 'firebase/functions' ||
        config.functions?.runtime !== 'nodejs22' || config.functions?.codebase !== 'public-feeds') {
        throw new Error('Functions source and Node 22 runtime must match the pinned local configuration.');
    }
    const allowed = ['functions', 'hub', 'logging', 'ui', 'singleProjectMode'];
    if (!selected.emulators || Object.keys(selected.emulators).some(key => !allowed.includes(key)) ||
        selected.emulators.ui?.enabled !== false || selected.emulators.singleProjectMode !== true) {
        throw new Error('The separate launcher must not start Auth, Firestore or a public UI.');
    }
    const result = { projectId };
    for (const [name, port] of [['functions', 5001], ['hub', 4401], ['logging', 4501]]) {
        const service = selected.emulators[name];
        if (service?.host !== '127.0.0.1' || service?.port !== port) {
            throw new Error('Functions launcher requires pinned loopback endpoints.');
        }
        result[name] = { host: service.host, port: service.port };
    }
    if (config.emulators.functions?.host !== '127.0.0.1' || config.emulators.functions?.port !== 5001) {
        throw new Error('Root Functions endpoint must match the pinned loopback endpoint.');
    }
    return result;
}

export function localFunctionsEnvironment(env, runtimeHome) {
    localFunctionsConfig(env);
    return {
        ...env, HOME: runtimeHome, USERPROFILE: runtimeHome,
        XDG_CONFIG_HOME: join(runtimeHome, '.config'), CLOUDSDK_CONFIG: join(runtimeHome, 'gcloud'),
        METADATA_SERVER_DETECTION: 'none',
        GCE_METADATA_HOST: '127.0.0.1:1', GCE_METADATA_IP: '127.0.0.1:1',
        GCLOUD_PROJECT: projectId, GOOGLE_CLOUD_PROJECT: projectId, GCP_PROJECT: projectId
    };
}