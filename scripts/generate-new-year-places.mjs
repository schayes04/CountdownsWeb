// Writes _data/new_year_places.json: the localized names of the first and last
// places to reach midnight (Kiribati, UTC+14, and American Samoa, UTC−11, the
// last inhabited zone) for the New Year page, using Intl.DisplayNames.
// Run after adding a locale: node scripts/generate-new-year-places.mjs
import { readFileSync, writeFileSync } from 'node:fs';
const names = {};
let code;
for (const line of readFileSync(new URL('../_data/locales.yml', import.meta.url), 'utf8').split('\n')) {
  const [key, value] = line.replace(/^\s*-?\s*/, '').split(/:\s*/);
  if (key === 'code' && line.startsWith('-')) code = value.replace(/['"]/g, '');
  if (key === 'html_lang' && code) {
    const regions = new Intl.DisplayNames([value.replace(/['"]/g, '')], { type: 'region' });
    names[code] = { first: regions.of('KI'), last: regions.of('AS') };
  }
}
writeFileSync(new URL('../_data/new_year_places.json', import.meta.url), `${JSON.stringify(names, null, 2)}\n`);
console.log(`Wrote New Year places for ${Object.keys(names).length} locales.`);
