// Vercel build step: writes public/config.js from environment variables (public/anon key only).
const fs = require('fs');
const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_ANON_KEY;
if (!url || !key) { console.error('Set SUPABASE_URL and SUPABASE_ANON_KEY in Vercel env vars.'); process.exit(1); }
fs.mkdirSync('public', { recursive: true });
fs.writeFileSync('public/config.js', `window.APP_CONFIG=${JSON.stringify({ SUPABASE_URL: url, SUPABASE_ANON_KEY: key })};`);
console.log('config.js written');
