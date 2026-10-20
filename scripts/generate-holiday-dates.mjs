import { readFileSync, writeFileSync } from 'node:fs';
import { holidayDate } from '../assets/holiday-dates.mjs';
import { regionalRules } from '../assets/holiday-country.mjs';

const source = new URL('../_data/holidays.json', import.meta.url);
const destination = new URL('../_data/holiday_dates.json', import.meta.url);
const holidays = JSON.parse(readFileSync(source, 'utf8'));
// Checked in so the normal GitHub Pages Jekyll build needs no custom plugin.
const years = rule => Array.from({ length: 101 }, (_, index) => holidayDate(rule, 2020 + index));
const dates = Object.fromEntries(holidays.map(holiday => [holiday.slug, years(holiday.rule)]));
// Regional observances ("slug@COUNTRY") let localized pages render local dates in static HTML.
for (const [country, observances] of Object.entries(regionalRules)) {
  for (const [slug, observance] of Object.entries(observances)) dates[`${slug}@${country}`] = years(observance.rule);
}
// Labels and sources for those observances, so the Jekyll templates can cite them too.
const regions = Object.fromEntries(Object.entries(regionalRules).map(([country, observances]) => [country,
  Object.fromEntries(Object.entries(observances).map(([slug, { label, source, sourceName }]) => [slug, { label, source, source_name: sourceName }]))
]));
const outputs = [
  [destination, `${JSON.stringify(dates, null, 2)}\n`],
  [new URL('../_data/holiday_regions.json', import.meta.url), `${JSON.stringify(regions, null, 2)}\n`]
];
if (process.argv.includes('--check')) {
  for (const [file, output] of outputs) {
    if (readFileSync(file, 'utf8') !== output) {
      throw new Error('Holiday dates changed. Run node scripts/generate-holiday-dates.mjs');
    }
  }
  console.log('Holiday date data is up to date (2020–2120).');
} else {
  for (const [file, output] of outputs) writeFileSync(file, output);
  console.log('Generated holiday dates for 2020–2120.');
}
