// Renders the 1200×630 link preview cards (og:image / twitter:image) for every website locale
// and rewrites _data/social_previews.yml. Run: node scripts/generate-social-previews.mjs [code ...]
// Needs Playwright with Chromium, Ruby (to read the YAML data), pngquant, and Noto fonts for
// non-Latin scripts (Debian/Ubuntu: fonts-noto-core fonts-noto-cjk).
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, readdirSync, unlinkSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { chromium } = playwright.default ?? playwright;
const root = new URL('..', import.meta.url).pathname;
const readYaml = (file) => JSON.parse(execFileSync('ruby', ['-ryaml', '-rjson', '-e',
  'puts JSON.generate(YAML.load_file(ARGV[0]))', join(root, file)], { encoding: 'utf8' }));

const locales = readYaml('_data/locales.yml');
const strings = readYaml('_data/strings.yml');
const screenshots = readYaml('_data/screenshots.yml').locales;
const outDir = join(root, 'assets/link-previews');
const only = process.argv.slice(2);

// en-CA shares the English artwork (see scripts/validate-social-previews.rb).
const shared = { 'en-CA': 'en' };

const cjkFont = { ja: 'Noto Sans CJK JP', ko: 'Noto Sans CJK KR', 'zh-Hans': 'Noto Sans CJK SC', 'zh-Hant': 'Noto Sans CJK TC' };
const fileUrl = (path) => pathToFileURL(join(root, path.replace(/^\//, ''))).href;
const escape = (text) => String(text).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

function card(locale) {
  const t = strings[locale.code] || strings.en;
  const shot = screenshots[locale.code]?.['home-screen-custom-widgets'] || screenshots.en['home-screen-custom-widgets'];
  const fonts = ['Inter', cjkFont[locale.code], 'Noto Sans', 'Noto Sans Arabic', 'Noto Sans Hebrew',
    'Noto Sans Devanagari', 'Noto Sans Thai', 'Noto Sans CJK JP', 'Noto Color Emoji', 'sans-serif']
    .filter(Boolean).map((f) => `"${f}"`).join(', ');
  return `<!doctype html><html lang="${locale.html_lang}" dir="${locale.dir}"><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; }
  html, body { width: 1200px; height: 630px; overflow: hidden; }
  body { font-family: ${fonts}; color: #fff; -webkit-font-smoothing: antialiased;
    background: radial-gradient(900px 600px at 85% 10%, #6f9cff 0%, transparent 60%),
                radial-gradient(700px 500px at 0% 100%, #1b2f7a 0%, transparent 70%),
                linear-gradient(135deg, #2a56c6 0%, #1d3c9c 55%, #172d78 100%);
    display: flex; align-items: center; padding-inline: 84px 0; }
  .copy { flex: 1; min-width: 0; padding-inline-end: 40px; }
  .icon { width: 132px; height: 132px; border-radius: 30px; display: block; margin-bottom: 34px;
    box-shadow: 0 18px 40px rgba(6, 18, 64, .45); }
  h1 { font-size: 88px; font-weight: 800; letter-spacing: -0.02em; line-height: 1.04; }
  p { margin-top: 20px; font-size: 40px; font-weight: 500; line-height: 1.22; color: rgba(255,255,255,.88); text-wrap: balance; }
  :lang(ko) p { word-break: keep-all; }
  .phone { flex: none; width: 470px; height: 630px; position: relative; margin-inline-end: 70px; }
  .frame { position: absolute; top: 44px; inset-inline: 0; height: 1040px; border-radius: 74px;
    background: #10131c; padding: 14px; box-shadow: 0 30px 80px rgba(4, 12, 48, .55), inset 0 0 0 2px #3a3f4d; }
  .frame img { width: 100%; border-radius: 60px; display: block; }
  </style></head><body>
  <div class="copy">
    <img class="icon" src="${fileUrl('/assets/appicon.png')}" alt="">
    <h1>${escape(locale.app_name)}</h1>
    <p>${escape(t.share_card_tagline)}</p>
  </div>
  <div class="phone"><div class="frame"><img src="${fileUrl(shot)}" alt=""></div></div>
  </body></html>`;
}

// Shrink the name and tagline until both fit inside the copy column.
async function fit(page) {
  await page.evaluate(async () => {
    await document.fonts.ready;
    const copy = document.querySelector('.copy');
    const h1 = document.querySelector('h1');
    const p = document.querySelector('p');
    const lines = (el) => Math.round(el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight));
    let h = 88;
    while (h > 52 && (h1.scrollWidth > copy.clientWidth || lines(h1) > 1)) h1.style.fontSize = `${h -= 2}px`;
    let s = 40;
    while (s > 28 && lines(p) > 3) p.style.fontSize = `${s -= 1}px`;
  });
}

const tmp = mkdtempSync(join(tmpdir(), 'link-previews-'));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
const manifest = readYaml('_data/social_previews.yml');
for (const locale of locales) {
  if (shared[locale.code] || (only.length && !only.includes(locale.code))) continue;
  const html = join(tmp, `${locale.code}.html`);
  writeFileSync(html, card(locale));
  await page.goto(pathToFileURL(html).href);
  await page.waitForLoadState('networkidle');
  await fit(page);
  const raw = join(tmp, `${locale.code}.png`);
  await page.screenshot({ path: raw });
  execFileSync('pngquant', ['--quality=80-95', '--speed=1', '--force', '--output', raw, raw]);
  const bytes = readFileSync(raw);
  const name = `${locale.code}.${createHash('sha256').update(bytes).digest('hex').slice(0, 12)}.png`;
  for (const old of readdirSync(outDir)) if (old.startsWith(`${locale.code}.`) && old !== name) unlinkSync(join(outDir, old));
  writeFileSync(join(outDir, name), bytes);
  manifest[locale.code] = `/assets/link-previews/${name}`;
  console.log(locale.code, name, `${Math.round(bytes.length / 1024)} KB`);
}
await browser.close();
for (const [code, source] of Object.entries(shared)) manifest[code] = manifest[source];

const ordered = locales.map((l) => `${l.code}: ${manifest[l.code]}`);
writeFileSync(join(root, '_data/social_previews.yml'),
  `# Localized 1200×630 link preview cards from scripts/generate-social-previews.mjs. Filenames contain the SHA-256 prefix.\n${ordered.join('\n')}\n`);
