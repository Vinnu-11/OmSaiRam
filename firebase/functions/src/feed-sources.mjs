import { createHash } from 'node:crypto';
import { isIP } from 'node:net';
import { load } from 'cheerio';

export const liveSource = 'https://sai.org.in/node/504?width=960&height=540&iframe=true';
export const festivalSource = 'https://sai.org.in/en/festivals';
export const maxHtmlBytes = 1024 * 1024;
export const maxEvents = 50;

export class FeedSourceError extends Error {
    constructor(code = 'source_unavailable') {
        super(code);
        this.code = code;
    }
}

export async function fetchUpstreamHtml(source, { fetchImpl = fetch, timeoutMs = 10000 } = {}) {
    if (![liveSource, festivalSource].includes(source) ||
        !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 10000) {
        throw new FeedSourceError('invalid_source');
    }
    const signal = AbortSignal.timeout(timeoutMs);
    let url = source;
    try {
        for (let redirects = 0; redirects <= 3; redirects++) {
            const response = await fetchImpl(url, { signal, redirect: 'manual', headers: { Accept: 'text/html' } });
            if ([301, 302, 303, 307, 308].includes(response.status)) {
                const location = response.headers.get('location');
                await response.body?.cancel();
                if (!location || redirects === 3) throw new FeedSourceError('invalid_redirect');
                const next = new URL(location, url);
                if (next.protocol !== 'https:' || !['sai.org.in', 'www.sai.org.in'].includes(next.hostname) ||
                    next.username || next.password || (next.port && next.port !== '443')) {
                    throw new FeedSourceError('invalid_redirect');
                }
                url = next.href;
                continue;
            }
            if (!response.ok || !response.headers.get('content-type')?.toLowerCase().startsWith('text/html') || !response.body) {
                await response.body?.cancel();
                throw new FeedSourceError();
            }
            if (Number(response.headers.get('content-length')) > maxHtmlBytes) {
                await response.body.cancel();
                throw new FeedSourceError('source_too_large');
            }
            const reader = response.body.getReader();
            const chunks = [];
            let size = 0;
            try {
                while (true) {
                    const part = await reader.read();
                    if (part.done) break;
                    size += part.value.byteLength;
                    if (size > maxHtmlBytes) {
                        await reader.cancel();
                        throw new FeedSourceError('source_too_large');
                    }
                    chunks.push(Buffer.from(part.value));
                }
            } finally {
                reader.releaseLock();
            }
            return Buffer.concat(chunks, size).toString('utf8');
        }
    } catch (error) {
        if (error instanceof FeedSourceError) throw error;
        throw new FeedSourceError();
    }
    throw new FeedSourceError();
}

function htmlDocument(html) {
    if (typeof html !== 'string' || Buffer.byteLength(html, 'utf8') > maxHtmlBytes) {
        throw new FeedSourceError('source_too_large');
    }
    return load(html);
}

export function streamUrl(value) {
    if (typeof value !== 'string' || value.length > 4096) throw new FeedSourceError('invalid_stream');
    let parsed;
    try { parsed = new URL(value); } catch { throw new FeedSourceError('invalid_stream'); }
    const host = parsed.hostname.replace(/^\[|\]$/g, '').replace(/\.$/, '');
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.hash ||
        (parsed.port && parsed.port !== '443') || isIP(host) || !host.includes('.') ||
        /(^|\.)(localhost|local|internal)$/.test(host) || !parsed.pathname.toLowerCase().endsWith('.m3u8')) {
        throw new FeedSourceError('invalid_stream');
    }
    return parsed.href;
}

export function parseLiveHtml(html) {
    const document = htmlDocument(html);
    const candidates = new Set();
    for (const script of document('script').toArray()) {
        for (const match of (document(script).html() ?? '').matchAll(/"newurl"\s*:\s*("(?:\\.|[^"\\])*")/g)) {
            try { candidates.add(streamUrl(JSON.parse(match[1]))); }
            catch { throw new FeedSourceError('invalid_stream'); }
        }
    }
    if (candidates.size !== 1) throw new FeedSourceError('invalid_stream');
    return { url: candidates.values().next().value };
}

const months = ['january', 'february', 'march', 'april', 'may', 'june', 'july',
    'august', 'september', 'october', 'november', 'december'];

export function festivalDate(label) {
    const numeric = label.match(/^(\d{1,2})([.\/-])(\d{1,2})\2(\d{4})$/);
    const named = label.match(/^([a-z]+)\s+(\d{1,2}),\s*(\d{4})$/i);
    const day = numeric ? Number(numeric[1]) : named ? Number(named[2]) : 0;
    const month = numeric ? Number(numeric[3]) : named ?
        months.findIndex(value => [value, value.slice(0, 3)].includes(named[1].toLowerCase())) + 1 : 0;
    const year = Number(numeric?.[4] ?? named?.[3] ?? 0);
    if (year < 1000 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    const date = new Date(Date.UTC(year, month - 1, day));
    return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
        ? date.toISOString().slice(0, 10) : null;
}

export function parseFestivalHtml(html) {
    const document = htmlDocument(html);
    const events = new Map();
    let truncated = false;
    const text = element => document(element).text().replace(/\s+/g, ' ').trim();
    function add(title, dateLabel, description) {
        if (!title || !dateLabel || /^(date|day|s\.?\s*no\.?|sr\.?\s*no\.?)$/i.test(dateLabel)) return;
        if (title.length > 255 || dateLabel.length > 100 || (description?.length ?? 0) > 2000) truncated = true;
        title = title.slice(0, 255);
        dateLabel = dateLabel.slice(0, 100);
        const key = JSON.stringify([title, dateLabel]);
        if (events.has(key)) return;
        events.set(key, {
            id: createHash('sha256').update(key).digest('hex'), title, dateLabel,
            eventDate: festivalDate(dateLabel), description: description?.slice(0, 2000) || null
        });
    }
    for (const row of document('table tr').toArray()) {
        const cells = document(row).children('td').toArray();
        if (cells.length >= 4 && (/^\d+\s*day$/i.test(text(cells[0])) || festivalDate(text(cells[3])) !== null)) {
            add(text(cells[1]), text(cells[3]), cells[4] ? text(cells[4]) : null);
        } else if (cells.length >= 2) {
            add(text(cells[1]), text(cells[0]), cells[2] ? text(cells[2]) : null);
        }
    }
    for (const heading of document('h2,h3,h4,strong').toArray()) {
        const title = text(heading);
        const dates = [...title.matchAll(/\d{1,2}[.\/]\d{1,2}[.\/]\d{4}/g)];
        if (dates.length !== 1) continue;
        const label = dates[0][0];
        const name = title.replace(label, '').replace(/^[\s,:\-\u2013\u2014]+|[\s,:\-\u2013\u2014]+$/g, '');
        add(name, label, document(heading).nextAll('p').first().text().replace(/\s+/g, ' ').trim());
    }
    if (!events.size) throw new FeedSourceError('invalid_festivals');
    const sorted = [...events.values()].sort((left, right) =>
        (left.eventDate ?? '9999-99-99').localeCompare(right.eventDate ?? '9999-99-99') ||
        left.title.localeCompare(right.title) || left.id.localeCompare(right.id));
    return { events: sorted.slice(0, maxEvents), truncated: truncated || sorted.length > maxEvents };
}