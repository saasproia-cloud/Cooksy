import { providerStatus, env } from "./config/env.js";

console.log(`APP_ENV=${env.APP_ENV}`);
console.log(`BACKEND_BASE_URL=${env.BACKEND_BASE_URL}`);
console.log(`OPENAI_CONFIGURED=${providerStatus.openAI ? 1 : 0}`);
console.log(`APIFY_CONFIGURED=${providerStatus.apify ? 1 : 0}`);
console.log(`SERPAPI_CONFIGURED=${providerStatus.serpApi ? 1 : 0}`);
console.log(`USDA_CONFIGURED=${providerStatus.usda ? 1 : 0}`);
