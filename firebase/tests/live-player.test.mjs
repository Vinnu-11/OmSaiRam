import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const html = await readFile(new URL('../../om_sai_ram/web/live_player.html', import.meta.url), 'utf8');
const script = html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
const endpoint = 'http://localhost:5001/demo-om-sai-ram/us-central1/liveDarshan';
const feed = () => {
    const fetched = Date.now(); return {
        url: 'https://stream.example.org/live.m3u8?token=fixture',
        sourceUrl: 'https://sai.org.in/node/504?width=960&height=540&iframe=true',
        fetchedAt: new Date(fetched).toISOString(), freshUntil: new Date(fetched + 30000).toISOString(), stale: false
    };
};
const settle = () => new Promise(resolve => setImmediate(resolve));

async function player({ query = `?feed=${encodeURIComponent(endpoint)}`, data = feed(), embedded = null, fetchImpl, hls = true } = {}) {
    const elements = new Map();
    const sources = [], requests = [], timers = [], listeners = new Map(), instances = [];
    function element(id) {
        if (!elements.has(id)) elements.set(id, {
            style: {}, textContent: embedded == null ? 'null' : JSON.stringify(embedded),
            pause() { }, load() { }, removeAttribute() { }, play: async () => { }, canPlayType: () => 'probably'
        });
        return elements.get(id);
    }
    class Hls {
        static DefaultConfig = { loader: class { } };
        static isSupported = () => true;
        static Events = { MANIFEST_PARSED: 'manifest', ERROR: 'error' };
        static ErrorTypes = { MEDIA_ERROR: 'media' };
        constructor() { this.handlers = {}; instances.push(this); }
        loadSource(source) { sources.push(source); }
        attachMedia() { }
        destroy() { this.destroyed = true; }
        on(name, callback) { this.handlers[name] = callback; if (name === 'manifest') callback(); }
    }
    const context = vm.createContext({
        document: { getElementById: element },
        window: { location: { search: query }, addEventListener: (name, callback) => listeners.set(name, callback) },
        ...(hls ? { Hls } : {}), URL, URLSearchParams, AbortController, TextDecoder, Uint8Array, ArrayBuffer,
        setTimeout: callback => { timers.push(callback); return timers.length; }, clearTimeout() { },
        fetch: async (url, options) => {
            requests.push({ url, options });
            return fetchImpl ? fetchImpl(url, options) : new Response(JSON.stringify(data), { headers: { 'content-type': 'application/json' } });
        },
    });
    vm.runInContext(script, context);
    await settle();
    return { context, elements, sources, requests, timers, listeners, instances };
}
const liveSource = 'https://sai.org.in/node/504?width=960&height=540&iframe=true';
const templePage = url => new Response(`<script>var x = {"newurl":${JSON.stringify(url)}};</script>`,
    { headers: { 'content-type': 'text/html; charset=utf-8' } });

test('Functions player requests only pinned feed, without credentials, redirect or signed iframe query', async () => {
    const fixture = feed();
    const result = await player({ data: fixture });
    assert.deepEqual(result.sources, [fixture.url]);
    assert.equal(result.requests[0].url, endpoint);
    assert.equal(result.requests[0].options.credentials, 'omit');
    assert.equal(result.requests[0].options.redirect, 'error');
    assert.equal(result.elements.get('spinner').style.display, 'none');
});

for (const query of ['?feed=https://remote.example/liveDarshan', `?feed=${encodeURIComponent(endpoint)}&api=http://localhost:8000`,
    `?feed=${encodeURIComponent(endpoint.replace('5001', '8000'))}`, `?feed=${encodeURIComponent(endpoint + '?url=bad')}`,
    `?feed=${encodeURIComponent(endpoint.replace('demo-om-sai-ram', 'production'))}`, '?feed=invalid']) {
    test(`invalid endpoint reads only the temple page, never legacy or remote: ${query}`, async () => {
        const result = await player({ query });
        assert.deepEqual(result.requests.map(r => r.url), [liveSource]); assert.equal(result.sources.length, 0);
        assert.equal(result.elements.get('error').style.display, 'block');
    });
}
for (const change of [{ stale: true }, { freshUntil: '2020-01-01T00:00:00.000Z' }, { url: 'http://stream.example.org/live.m3u8' },
{ url: 'https://127.0.0.1/live.m3u8' }, { url: 'https://stream.local./live.m3u8' },
{ url: 'https://user:pass@stream.example.org/live.m3u8' }, { url: 'https://stream.example.org/live.m3u8#secret' },
{ extra: 'unsupported' }, { fetchedAt: '2026-02-30T00:00:00.000Z' }]) {
    test(`malformed/expired stream fails closed: ${Object.keys(change)[0]} ${Object.values(change)[0]}`, async () => {
        const result = await player({ data: { ...feed(), ...change } });
        assert.equal(result.sources.length, 0); assert.equal(result.elements.get('error').style.display, 'block');
    });
}
test('502, wrong content type and oversized responses fail without legacy request', async () => {
    for (const response of [new Response('{}', { status: 502 }), new Response('{}'),
    new Response('x'.repeat(262145), { headers: { 'content-type': 'application/json' } })]) {
        const result = await player({ fetchImpl: () => response });
        assert.deepEqual(result.requests.map(r => r.url), [endpoint, liveSource]); assert.equal(result.sources.length, 0);
        assert.equal(result.elements.get('error').style.display, 'block');
    }
});
test('feed service down: the stream comes straight from the temple page', async () => {
    const stream = 'https://cam.example.org/live/playlist.m3u8?e=1&h=x';
    const result = await player({ fetchImpl: url => url === endpoint ? Promise.reject(new TypeError('refused')) : templePage(stream) });
    assert.deepEqual(result.requests.map(r => r.url), [endpoint, liveSource]);
    assert.equal(result.requests[1].options.credentials, 'omit');
    assert.deepEqual(result.sources, [stream]);
    const direct = await player({ query: '?direct=1', fetchImpl: () => templePage(stream) });
    assert.deepEqual(direct.requests.map(r => r.url), [liveSource]); assert.deepEqual(direct.sources, [stream]);
    for (const bad of ['http://cam.example.org/live.m3u8', 'https://127.0.0.1/live.m3u8']) {
        const unsafe = await player({ query: '?direct=1', fetchImpl: () => templePage(bad) });
        assert.equal(unsafe.sources.length, 0); assert.equal(unsafe.elements.get('error').style.display, 'block');
    }
});
test('dropped playback fetches a fresh stream three times, then shows Retry; playing resets', async () => {
    const result = await player();
    const drop = () => result.instances.at(-1).handlers.error('error', { fatal: true, type: 'network' });
    for (let i = 0; i < 3; i++) {
        drop();
        assert.notEqual(result.elements.get('error').style.display, 'block');
        result.timers.at(-1)(); await settle();
    }
    assert.equal(result.requests.length, 4); assert.equal(result.sources.length, 4);
    drop(); assert.equal(result.elements.get('error').style.display, 'block');
    result.context.retryStream(); await settle();
    result.elements.get('video').onplaying();
    drop(); assert.notEqual(result.elements.get('error').style.display, 'block');
});
test('embedded Android data never fetches legacy/Functions from opaque-origin HTML; retry bridges a new native read', async () => {
    const fixture = feed(); const result = await player({ query: '', embedded: fixture });
    assert.equal(result.requests.length, 0); assert.deepEqual(result.sources, [fixture.url]);
    let retries = 0; result.context.FirebaseFeedRetry = { postMessage: () => retries++ };
    result.context.retryStream(); assert.equal(retries, 1);
    const messages = []; result.context.FirebaseFeedRetry = { postMessage: m => messages.push(m) };
    result.elements.get('video').onplaying();
    result.instances.at(-1).handlers.error('error', { fatal: true, type: 'network' });
    result.timers.at(-1)();
    assert.deepEqual(messages, ['playing', 'auto']); assert.equal(result.requests.length, 0);
});
test('retry discards earlier response; pagehide aborts pending work', async () => {
    let resolveFirst; let calls = 0;
    const result = await player({
        fetchImpl: () => {
            if (++calls === 1) return new Promise(resolve => { resolveFirst = resolve; });
            return new Response(JSON.stringify(feed()), { headers: { 'content-type': 'application/json' } });
        }
    });
    await result.context.loadStream();
    const count = result.sources.length;
    resolveFirst(new Response(JSON.stringify(feed()), { headers: { 'content-type': 'application/json' } }));
    await settle(); assert.equal(result.sources.length, count);
    result.listeners.get('pagehide')(); assert.equal(result.requests.at(-1).options.signal.aborted, true);
});
test('default legacy endpoint and native Safari fallback remain supported without hls.js', async () => {
    const result = await player({ query: '?api=http://localhost:8000/api/v1', hls: false });
    assert.equal(result.requests[0].url, 'http://localhost:8000/api/v1/live-darshan/stream-url');
    assert.equal(result.elements.get('video').src, feed().url);
});