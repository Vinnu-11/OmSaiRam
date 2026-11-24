import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import {
    festivalDate, festivalSource, fetchUpstreamHtml, liveSource, maxHtmlBytes,
    parseFestivalHtml, parseLiveHtml, streamUrl
} from '../src/feed-sources.mjs';

const html = body => new Response(body, { headers: { 'content-type': 'text/html; charset=utf-8' } });
const stream = 'https://stream.example.org/live.m3u8?token=fixture&second=1';

test('live settings use JSON unescaping without copying a whole script or losing query parameters', () => {
    const value = JSON.stringify(stream).replaceAll('/', '\\/').replace('&', '\\u0026');
    assert.equal(parseLiveHtml(`<script>settings = {"newurl":${value}};</script>`).url, stream);
});
test('duplicate live settings agree, ambiguous or missing streams fail closed', () => {
    const script = `<script>{"newurl":${JSON.stringify(stream)}}</script>`;
    assert.equal(parseLiveHtml(script + script).url, stream);
    assert.throws(() => parseLiveHtml(script + '<script>{"newurl":"https://stream.example.org/other.m3u8"}</script>'));
    assert.throws(() => parseLiveHtml('<p>Stream offline</p>'));
});
for (const value of ['http://stream.example.org/live.m3u8', 'https://127.0.0.1/live.m3u8',
    'https://[::1]/live.m3u8', 'https://stream.local/live.m3u8', 'https://localhost/live.m3u8',
    'https://localhost./live.m3u8', 'https://stream.local./live.m3u8', 'https://stream.internal./live.m3u8',
    'https://user:secret@stream.example.org/live.m3u8', 'https://stream.example.org:5001/live.m3u8',
    'https://stream.example.org/live.m3u8#fragment', 'https://stream.example.org/live.html', 'not a URL']) {
    test(`unsafe stream URL rejected: ${value}`, () => assert.throws(() => streamUrl(value)));
}
for (const [label, expected] of [['28.07.2026', '2026-07-28'], ['28/07/2026', '2026-07-28'],
['28-07-2026', '2026-07-28'], ['July 28, 2026', '2026-07-28'], ['Jul 28, 2026', '2026-07-28'],
['29.02.2028', '2028-02-29'], ['29.02.2026', null], ['31.04.2026', null], ['28.07/2026', null],
['Januaryx 28, 2026', null], ['28-30 July 2026', null], ['Date pending', null]]) {
    test(`festival date is literal and calendar-valid: ${label}`, () => assert.equal(festivalDate(label), expected));
}
test('festival table parses text/entities, ignores headers, deduplicates and orders unknown dates last', () => {
    const parsed = parseFestivalHtml(`<table><tr><th>Date</th><th>Event</th></tr>
        <tr><td>Pending</td><td>Undated event</td></tr>
        <tr><td>28.07.2026</td><td>Guru &amp; Pournima</td><td><p>Actual description</p></td></tr>
        <tr><td>28.07.2026</td><td>Guru &amp; Pournima</td></tr></table>`);
    assert.equal(parsed.events.length, 2); assert.equal(parsed.events[0].title, 'Guru & Pournima');
    assert.equal(parsed.events[0].description, 'Actual description');
    assert.equal(parsed.events[1].eventDate, null); assert.equal(parsed.truncated, false);
});
test('festival heading uses only an explicit date, not guessed surrounding text', () => {
    const parsed = parseFestivalHtml('<h3>Guru Pournima - 28.07.2026</h3><p>Celebration</p><h3>Diwali</h3>');
    assert.equal(parsed.events.length, 1); assert.equal(parsed.events[0].title, 'Guru Pournima');
    assert.equal(parsed.events[0].eventDate, '2026-07-28');
});
test('temple four-column day/title/weekday/date layout maps the explicit date, not the day ordinal', () => {
    const parsed = parseFestivalHtml(`<table>
        <tr><td>2Day</td><td>Main day</td><td>Tuesday</td><td>20.10.2026</td></tr>
        <tr><td>1Day</td><td>Opening day</td><td>Monday</td><td>19.10.2026</td></tr>
        <tr><td>3Day</td><td>Unconfirmed day</td><td>Pending</td><td>Date pending</td></tr></table>`);
    assert.equal(parsed.events[0].title, 'Opening day'); assert.equal(parsed.events[0].dateLabel, '19.10.2026');
    assert.equal(parsed.events[0].eventDate, '2026-10-19'); assert.equal(parsed.events[0].description, null);
    assert.equal(parsed.events[1].eventDate, '2026-10-20'); assert.equal(parsed.events[2].eventDate, null);
    assert.equal(parsed.events[2].dateLabel, 'Date pending');
});
test('festival bounds and truncation are explicit; empty/error pages do not become successful empty calendars', () => {
    const rows = Array.from({ length: 60 }, (_, index) => `<tr><td>Pending</td><td>Event ${index}</td><td>${'x'.repeat(2200)}</td></tr>`).join('');
    const parsed = parseFestivalHtml(`<table>${rows}</table>`);
    assert.equal(parsed.events.length, 50); assert.equal(parsed.truncated, true);
    assert.equal(parsed.events[0].description.length, 2000);
    assert.throws(() => parseFestivalHtml('<h1>Challenge</h1>'));
    assert.throws(() => parseFestivalHtml('x'.repeat(maxHtmlBytes + 1)));
});
test('source HTTP uses fixed URL, manual redirects, timeout and bounded HTML', async () => {
    const calls = [];
    assert.equal(await fetchUpstreamHtml(liveSource, {
        fetchImpl: async (url, options) => {
            calls.push({ url, options }); return html('fixture');
        }
    }), 'fixture');
    assert.equal(calls[0].url, liveSource); assert.equal(calls[0].options.redirect, 'manual');
    assert.ok(calls[0].options.signal instanceof AbortSignal);
    await assert.rejects(fetchUpstreamHtml('http://localhost/anything'));
});
test('source redirects stay on trusted HTTPS temple hosts and have a hard limit', async () => {
    let calls = 0;
    assert.equal(await fetchUpstreamHtml(festivalSource, {
        fetchImpl: async () => ++calls === 1
            ? new Response(null, { status: 302, headers: { location: 'https://www.sai.org.in/en/festivals' } }) : html('fixture')
    }), 'fixture');
    for (const location of ['http://sai.org.in/en/festivals', 'https://127.0.0.1/', 'https://evil.example.org/', 'https://sai.org.in:5001/']) {
        await assert.rejects(fetchUpstreamHtml(festivalSource, {
            fetchImpl: async () =>
                new Response(null, { status: 302, headers: { location } })
        }));
    }
    calls = 0;
    await assert.rejects(fetchUpstreamHtml(festivalSource, {
        fetchImpl: async () => {
            calls++; return new Response(null, { status: 302, headers: { location: '/en/festivals' } });
        }
    })); assert.equal(calls, 4);
});
test('non-HTML, HTTP errors, network failures and oversized decoded bodies fail safely', async () => {
    for (const response of [new Response('{}', { headers: { 'content-type': 'application/json' } }),
    new Response('offline', { status: 503 }), html('x'.repeat(maxHtmlBytes + 1)),
    new Response('small', { headers: { 'content-type': 'text/html', 'content-length': String(maxHtmlBytes + 1) } })]) {
        await assert.rejects(fetchUpstreamHtml(festivalSource, { fetchImpl: async () => response }));
    }
    await assert.rejects(fetchUpstreamHtml(festivalSource, { fetchImpl: async () => { throw new Error('private upstream details'); } }),
        error => error.message === 'source_unavailable');
});
test('native fetch deadline aborts a stalled HTML response body', async () => {
    const server = createServer((request, response) => {
        response.writeHead(200, { 'content-type': 'text/html' }); response.write('<html>');
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try {
        const url = `http://127.0.0.1:${server.address().port}/fixture`;
        await assert.rejects(fetchUpstreamHtml(festivalSource, {
            timeoutMs: 30,
            fetchImpl: (_, options) => fetch(url, options)
        }), error => error.code === 'source_unavailable');
    } finally {
        server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    }
});