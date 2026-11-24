import test from 'node:test';
import assert from 'node:assert/strict';
import { createFeedHandlers, localRuntime, projectId } from '../src/feed-http.mjs';
import { liveDarshan, festivals } from '../index.mjs';

const local = {
    FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: projectId, METADATA_SERVER_DETECTION: 'none',
    GCE_METADATA_HOST: '127.0.0.1:1', GCE_METADATA_IP: '127.0.0.1:1'
};
function fixture(env = local) {
    let calls = 0;
    let failure = false;
    const read = async () => { calls++; if (failure) throw new Error('secret source payload'); return { fixture: true }; };
    const handlers = createFeedHandlers({ env: () => env, service: { liveDarshan: read, festivals: read } });
    return { handlers, calls: () => calls, fail: () => { failure = true; } };
}
async function invoke(handler, changes = {}) {
    const result = { status: null, headers: {}, body: null };
    const response = {
        set(key, value) { result.headers[key] = value; return this; },
        status(value) { result.status = value; return this; }, json(value) { result.body = value; return this; },
        end() { return this; }
    };
    await handler({ method: 'GET', path: '/', query: {}, headers: {}, ...changes }, response);
    return result;
}
test('Functions SDK exports discoverable HTTP functions without source I/O at import', () => {
    assert.equal(liveDarshan.__endpoint.platform, 'gcfv2'); assert.equal(festivals.__endpoint.platform, 'gcfv2');
    assert.deepEqual(liveDarshan.__endpoint.region, ['us-central1']);
});
for (const env of [{}, { ...local, FUNCTIONS_EMULATOR: 'false' }, { ...local, GCLOUD_PROJECT: 'live-project' },
{ ...local, METADATA_SERVER_DETECTION: 'assume-present' },
{ ...local, GCE_METADATA_HOST: 'metadata.google.internal' },
{ ...local, google_application_credentials: '/private/fixture.json' },
{ ...local, GOOGLE_CLOUD_PROJECT: 'live-project' }, { ...local, GCP_PROJECT: 'live-project' },
{ ...local, FIREBASE_CONFIG: '{bad' }, { ...local, FIREBASE_CONFIG: '{"projectId":"live-project"}' },
{ ...local, GOOGLE_APPLICATION_CREDENTIALS: '/private/key.json' }]) {
    test(`runtime guard rejects nonlocal/credential configuration ${JSON.stringify(env)}`, async () => {
        assert.equal(localRuntime(env), false); const f = fixture(env);
        assert.equal((await invoke(f.handlers.festivals)).status, 503); assert.equal(f.calls(), 0);
    });
}
for (const origin of ['https://localhost:8790', 'http://evil.example.org', 'null', 'http://localhost.evil.org:8790',
    'http://localhost:8790/path', 'http://user:password@localhost:8790']) {
    test(`CORS rejects non-loopback origin ${origin}`, async () => {
        const f = fixture(); assert.equal((await invoke(f.handlers.liveDarshan, { headers: { origin } })).status, 403);
        assert.equal(f.calls(), 0);
    });
}
for (const origin of ['http://localhost:8790', 'http://127.0.0.1:8790']) {
    test(`public GET supports local origin ${origin} without auth/profile reads`, async () => {
        const f = fixture(); const result = await invoke(f.handlers.liveDarshan, { headers: { origin } });
        assert.equal(result.status, 200); assert.equal(result.headers['Access-Control-Allow-Origin'], origin);
        assert.equal(result.headers['Cache-Control'], 'no-store'); assert.deepEqual(result.body, { fixture: true });
    });
}
for (const method of ['POST', 'PUT', 'DELETE', 'PATCH', 'HEAD']) {
    test(`unsupported method ${method} cannot force an upstream refresh`, async () => {
        const f = fixture(); const result = await invoke(f.handlers.festivals, { method });
        assert.equal(result.status, 405); assert.equal(f.calls(), 0);
    });
}
for (const changes of [{ query: { url: 'http://127.0.0.1/' } }, { query: { refresh: 'true' } },
{ headers: { 'content-length': '2' } }, { headers: { 'transfer-encoding': 'chunked' } }]) {
    test(`query/body input cannot alter trusted source ${JSON.stringify(changes)}`, async () => {
        const f = fixture(); assert.equal((await invoke(f.handlers.festivals, changes)).status, 400); assert.equal(f.calls(), 0);
    });
}
test('local GET preflight is supported without invoking source; other methods/headers are rejected', async () => {
    const f = fixture(); const headers = { origin: 'http://localhost:8790', 'access-control-request-method': 'GET' };
    assert.equal((await invoke(f.handlers.festivals, { method: 'OPTIONS', headers })).status, 204);
    assert.equal((await invoke(f.handlers.festivals, { method: 'OPTIONS', headers: { ...headers, 'access-control-request-method': 'POST' } })).status, 405);
    assert.equal((await invoke(f.handlers.festivals, { method: 'OPTIONS', headers: { ...headers, 'access-control-request-headers': 'authorization' } })).status, 400);
    assert.equal(f.calls(), 0);
});
test('source failures have safe JSON with no tokens, HTML, credentials or internal exceptions', async () => {
    const f = fixture(); f.fail(); const result = await invoke(f.handlers.liveDarshan);
    assert.equal(result.status, 502); assert.equal(result.body.error.code, 'upstream_unavailable');
    assert.ok(!JSON.stringify(result).includes('secret')); assert.equal(result.headers['Cache-Control'], 'no-store');
});
test('runtime is rechecked on every request and unknown subroutes do not fetch', async () => {
    const env = { ...local }; const f = fixture(env);
    assert.equal((await invoke(f.handlers.liveDarshan, { path: '/refresh' })).status, 404);
    assert.equal((await invoke(f.handlers.liveDarshan)).status, 200);
    env.FUNCTIONS_EMULATOR = 'false'; assert.equal((await invoke(f.handlers.liveDarshan)).status, 503);
    assert.equal(f.calls(), 1);
});