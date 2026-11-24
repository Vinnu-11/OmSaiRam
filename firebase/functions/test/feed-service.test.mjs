import test from 'node:test';
import assert from 'node:assert/strict';
import { createFeedService, feedTiming } from '../src/feed-service.mjs';
import { liveSource, festivalSource } from '../src/feed-sources.mjs';

const streamHtml = '<script>{"newurl":"https://stream.example.org/live.m3u8?token=fixture"}</script>';
const festivalsHtml = '<table><tr><td>28.07.2026</td><td>Guru Pournima</td></tr></table>';
function fixture() {
    let time = 10000;
    let failed = false;
    let gate;
    const calls = [];
    const service = createFeedService({
        now: () => time, fetchHtml: async source => {
            calls.push(source);
            if (gate) await gate;
            if (failed) throw new Error('private source details');
            return source === liveSource ? streamHtml : festivalsHtml;
        }
    });
    return {
        service, calls, setTime: value => { time = value; }, fail: () => { failed = true; },
        recover: () => { failed = false; }, gate: value => { gate = value; }
    };
}
test('fresh cache returns metadata and needs no repeated upstream requests', async () => {
    const f = fixture(); const first = await f.service.liveDarshan();
    const next = await f.service.liveDarshan();
    assert.equal(f.calls.length, 1); assert.deepEqual(next, first);
    assert.equal(first.stale, false); assert.equal(first.sourceUrl, liveSource);
    assert.equal(Date.parse(first.freshUntil) - Date.parse(first.fetchedAt), feedTiming.liveFresh);
});
test('concurrent cold requests share one in-flight upstream read', async () => {
    const f = fixture(); let release; f.gate(new Promise(resolve => { release = resolve; }));
    const reads = Array.from({ length: 20 }, () => f.service.festivals());
    assert.equal(f.calls.length, 1); release();
    const responses = await Promise.all(reads);
    assert.ok(responses.every(value => value.stale === false)); assert.equal(f.calls[0], festivalSource);
});
test('expired stream never falls back to an old URL; cooldown stops failure hammering', async () => {
    const f = fixture(); await f.service.liveDarshan(); f.fail(); f.setTime(10000 + feedTiming.liveFresh);
    await assert.rejects(f.service.liveDarshan()); await assert.rejects(f.service.liveDarshan());
    assert.equal(f.calls.length, 2);
    f.recover(); f.setTime(10000 + feedTiming.liveFresh + feedTiming.failureCooldown);
    assert.equal((await f.service.liveDarshan()).stale, false); assert.equal(f.calls.length, 3);
});
test('festival failure preserves last successful metadata, explicitly stale, only within maximum age', async () => {
    const f = fixture(); const first = await f.service.festivals(); f.fail(); f.setTime(10000 + feedTiming.festivalFresh);
    const stale = await f.service.festivals();
    assert.equal(stale.stale, true); assert.equal(stale.fetchedAt, first.fetchedAt);
    assert.deepEqual(stale.events, first.events); assert.equal(stale.freshUntil, first.freshUntil);
    await f.service.festivals(); assert.equal(f.calls.length, 2);
    f.setTime(10000 + feedTiming.festivalMaximumAge); await assert.rejects(f.service.festivals());
});
test('cold failure or invalid parsed source does not create successful empty feed cache', async () => {
    const f = fixture(); f.fail(); await assert.rejects(f.service.festivals());
    const invalid = createFeedService({ fetchHtml: async () => '<h1>Unavailable</h1>' });
    await assert.rejects(invalid.festivals()); await assert.rejects(invalid.liveDarshan());
});
test('live and festival caches are separate, and exposed cached events cannot be mutated', async () => {
    const f = fixture(); const first = await f.service.festivals(); await f.service.liveDarshan();
    assert.deepEqual(f.calls, [festivalSource, liveSource]);
    assert.throws(() => first.events.push({ title: 'forged' }));
    assert.throws(() => { first.events[0].title = 'forged'; });
    assert.throws(() => { first.stale = true; });
    assert.equal((await f.service.festivals()).events[0].title, 'Guru Pournima');
});
test('clock moving backwards never treats a future cache as freshly fetched', async () => {
    const f = fixture(); await f.service.festivals(); f.fail(); f.setTime(9999);
    await assert.rejects(f.service.festivals());
});
test('restarting service loses process-local cache rather than claiming a durable feed', async () => {
    const f = fixture(); await f.service.festivals();
    const restarted = createFeedService({ fetchHtml: async () => { throw new Error('offline'); } });
    await assert.rejects(restarted.festivals());
});