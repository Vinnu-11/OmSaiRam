import { createFeedService } from './feed-service.mjs';

export const projectId = 'demo-om-sai-ram';

export function localRuntime(env) {
    if (env.FUNCTIONS_EMULATOR !== 'true' || env.GCLOUD_PROJECT !== projectId || env.METADATA_SERVER_DETECTION !== 'none' ||
        env.GCE_METADATA_HOST !== '127.0.0.1:1' || env.GCE_METADATA_IP !== '127.0.0.1:1' ||
        env.GOOGLE_APPLICATION_CREDENTIALS || env.google_application_credentials || env.FIREBASE_TOKEN ||
        ['GOOGLE_CLOUD_PROJECT', 'GCP_PROJECT'].some(key => env[key] && env[key] !== projectId)) return false;
    if (env.FIREBASE_CONFIG) {
        try {
            if (JSON.parse(env.FIREBASE_CONFIG).projectId !== projectId) return false;
        } catch { return false; }
    }
    return true;
}

function localOrigin(value) {
    try {
        const url = new URL(value);
        return url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname) && url.origin === value;
    } catch { return false; }
}

export function createFeedHandlers({ service = createFeedService(), env = () => process.env } = {}) {
    const handler = name => async (request, response) => {
        response.set('Cache-Control', 'no-store');
        response.set('X-Content-Type-Options', 'nosniff');
        const error = (status, code, message) => response.status(status).json({ error: { code, message } });
        if (!localRuntime(env())) return error(503, 'local_runtime_required', 'This service requires the local demo Functions emulator.');
        const origin = request.headers.origin;
        if (origin && !localOrigin(origin)) return error(403, 'origin_denied', 'Only local development browser origins are supported.');
        if (origin) {
            response.set('Access-Control-Allow-Origin', origin);
            response.set('Vary', 'Origin');
        }
        response.set('Allow', 'GET, OPTIONS');
        if (request.method === 'OPTIONS') {
            if (request.headers['access-control-request-method'] && request.headers['access-control-request-method'] !== 'GET') {
                return error(405, 'method_not_allowed', 'Only GET is supported.');
            }
            if ((request.headers['access-control-request-headers'] ?? '').split(',').some(header =>
                header.trim() && !['accept', 'content-type'].includes(header.trim().toLowerCase()))) {
                return error(400, 'unsupported_headers', 'The requested browser headers are not supported.');
            }
            response.set('Access-Control-Allow-Methods', 'GET');
            response.set('Access-Control-Allow-Headers', 'Accept, Content-Type');
            return response.status(204).end();
        }
        if (request.method !== 'GET') return error(405, 'method_not_allowed', 'Only GET is supported.');
        if (request.path && request.path !== '/') return error(404, 'not_found', 'This service has no subroutes.');
        if (Object.keys(request.query ?? {}).length || Number(request.headers['content-length'] ?? 0) > 0 ||
            request.headers['transfer-encoding']) {
            return error(400, 'unsupported_input', 'Query parameters and request bodies are not supported.');
        }
        try {
            return response.status(200).json(await service[name]());
        } catch {
            return error(502, 'upstream_unavailable', 'The source feed is unavailable. Try again later.');
        }
    };
    return Object.freeze({ liveDarshan: handler('liveDarshan'), festivals: handler('festivals') });
}