import assert from 'node:assert/strict';
import { localFunctionsConfig, projectId } from './local-config.mjs';
import { streamUrl, festivalDate, liveSource, festivalSource } from '../functions/src/feed-sources.mjs';

if (process.argv.slice(2).some(value => value !== '--require-live')) throw new Error('Only --require-live is supported.');
const requireLive = process.argv.includes('--require-live');
const { host, port } = localFunctionsConfig().functions;
const base = `http://${host}:${port}/${projectId}/us-central1/`;
for (const name of ['liveDarshan', 'festivals']) {
    for (const [suffix, options, status] of [
        ['', { method: 'POST' }, 405], ['?refresh=true', {}, 400],
        ['', { headers: { Origin: 'http://evil.example.org' } }, 403],
        ['', { method: 'OPTIONS', headers: { Origin: 'http://localhost:8790', 'Access-Control-Request-Method': 'GET' } }, 204],
    ]) {
        const response = await fetch(base + name + suffix, { ...options, redirect: 'error', signal: AbortSignal.timeout(10000) });
        assert.equal(response.status, status, `${name}: expected guarded HTTP response.`);
        await response.body?.cancel();
    }
    const response = await fetch(base + name, { redirect: 'error', headers: { Origin: 'http://localhost:8790' }, signal: AbortSignal.timeout(20000) });
    assert.equal(response.headers.get('access-control-allow-origin'), 'http://localhost:8790');
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.ok([200, 502].includes(response.status), `${name}: runtime must respond, independently of source availability.`);
    const data = await response.json();
    if (requireLive) assert.equal(response.status, 200, `${name}: live-source verification requires success.`);
    if (response.status === 200) {
        assert.equal(typeof data.stale, 'boolean');
        assert.equal(new Date(data.fetchedAt).toISOString(), data.fetchedAt);
        assert.equal(new Date(data.freshUntil).toISOString(), data.freshUntil);
        assert.equal(data.sourceUrl, name === 'liveDarshan' ? liveSource : festivalSource);
        if (name === 'liveDarshan') {
            assert.equal(streamUrl(data.url), data.url); assert.equal(data.stale, false);
        } else {
            assert.ok(Array.isArray(data.events) && data.events.length > 0 && data.events.length <= 50);
            assert.equal(typeof data.truncated, 'boolean');
            for (const event of data.events) {
                assert.match(event.id, /^[0-9a-f]{64}$/);
                assert.equal(event.eventDate, festivalDate(event.dateLabel));
                assert.ok(event.title.trim() && event.title.length <= 255);
            }
        }
    } else {
        assert.equal(data.error?.code, 'upstream_unavailable');
    }
    console.log(JSON.stringify({
        service: name, status: response.status, stale: data.stale ?? null,
        eventCount: data.events?.length ?? null, error: data.error?.code ?? null, httpGuards: 'passed'
    }));
}