// Writes _data/milestone_labels.json: "100 days", "1 year" and so on in every
// site locale, from the same Intl formatting the calculator uses in the browser,
// so the milestone table reads correctly before (and without) JavaScript.
// Run after adding a locale: node scripts/generate-milestone-labels.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { toolFormatters } from '../assets/tool-i18n.mjs';
import { MILESTONE_STEPS as MILESTONES } from '../assets/anniversary-dates.mjs';
// Each locales.yml entry starts with "- code:" and has an html_lang line.
const labels = {};
let code;
for (const line of readFileSync(new URL('../_data/locales.yml', import.meta.url), 'utf8').split('\n')) {
  const [key, value] = line.replace(/^\s*-?\s*/, '').split(/:\s*/);
  if (key === 'code' && line.startsWith('-')) code = value.replace(/['"]/g, '');
  if (key === 'html_lang' && code) labels[code] = MILESTONES.map(([unit, count]) => toolFormatters(value.replace(/['"]/g, '')).unit(count, unit));
}
writeFileSync(new URL('../_data/milestone_labels.json', import.meta.url), `${JSON.stringify(labels, null, 2)}\n`);
console.log(`Wrote milestone labels for ${Object.keys(labels).length} locales.`);
