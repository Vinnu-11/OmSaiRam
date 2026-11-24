import { onRequest } from 'firebase-functions/v2/https';
import { createFeedHandlers } from './src/feed-http.mjs';

const handlers = createFeedHandlers();
const options = { region: 'us-central1', cors: false, timeoutSeconds: 30, memory: '256MiB', maxInstances: 1 };
export const liveDarshan = onRequest(options, handlers.liveDarshan);
export const festivals = onRequest(options, handlers.festivals);