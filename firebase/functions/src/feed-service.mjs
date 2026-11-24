import {
    FeedSourceError, fetchUpstreamHtml, liveSource, festivalSource,
    parseLiveHtml, parseFestivalHtml
} from './feed-sources.mjs';

export const feedTiming = Object.freeze({
    liveFresh: 30000, festivalFresh: 6 * 60 * 60 * 1000,
    festivalMaximumAge: 7 * 24 * 60 * 60 * 1000, failureCooldown: 60000
});

class FeedCache {
    #saved;
    #pending;
    #failedAt;
    constructor(source, parse, freshFor, maximumAge, fetchHtml, now) {
        Object.assign(this, { source, parse, freshFor, maximumAge, fetchHtml, now });
    }
    #result(stale) {
        return Object.freeze({
            ...this.#saved.value, sourceUrl: this.source,
            fetchedAt: new Date(this.#saved.time).toISOString(),
            freshUntil: new Date(this.#saved.time + this.freshFor).toISOString(), stale
        });
    }
    #fallback() {
        const time = this.now();
        if (this.#saved && time >= this.#saved.time && time - this.#saved.time < this.maximumAge) {
            return this.#result(true);
        }
        throw new FeedSourceError();
    }
    async read() {
        const time = this.now();
        if (this.#saved && time >= this.#saved.time && time - this.#saved.time < this.freshFor) {
            return this.#result(false);
        }
        if (this.#pending) return this.#pending;
        if (this.#failedAt !== undefined && time >= this.#failedAt && time - this.#failedAt < feedTiming.failureCooldown) {
            return this.#fallback();
        }
        this.#pending = this.#refresh();
        try { return await this.#pending; }
        finally { this.#pending = undefined; }
    }
    async #refresh() {
        try {
            const value = this.parse(await this.fetchHtml(this.source));
            if (value.events) {
                value.events = Object.freeze(value.events.map(event => Object.freeze(event)));
            }
            this.#saved = { value: Object.freeze(value), time: this.now() };
            this.#failedAt = undefined;
            return this.#result(false);
        } catch {
            this.#failedAt = this.now();
            return this.#fallback();
        }
    }
}

export function createFeedService({ fetchHtml = fetchUpstreamHtml, now = Date.now } = {}) {
    const live = new FeedCache(liveSource, parseLiveHtml, feedTiming.liveFresh, 0, fetchHtml, now);
    const festival = new FeedCache(festivalSource, parseFestivalHtml, feedTiming.festivalFresh,
        feedTiming.festivalMaximumAge, fetchHtml, now);
    return Object.freeze({ liveDarshan: () => live.read(), festivals: () => festival.read() });
}