import { readFileSync, writeFileSync } from 'node:fs';
import { holidayDate } from '../assets/holiday-dates.mjs';

const source = new URL('../_data/holidays.json', import.meta.url);
const destination = new URL('../_data/holiday_dates.json', import.meta.url);
const holidays = JSON.parse(readFileSync(source, 'utf8'));
// Checked in so the normal GitHub Pages Jekyll build needs no custom plugin.
const dates = Object.fromEntries(holidays.map(holiday => [holiday.slug,
  Array.from({ length: 101 }, (_, index) => holidayDate(holiday.rule, 2020 + index))
]));
const output = `${JSON.stringify(dates, null, 2)}\n`;
if (process.argv.includes('--check')) {
  if (readFileSync(destination, 'utf8') !== output) {
    throw new Error('Holiday dates changed. Run node scripts/generate-holiday-dates.mjs');
  }
  console.log('Holiday date data is up to date (2020–2120).');
} else {
  writeFileSync(destination, output);
  console.log('Generated holiday dates for 2020–2120.');
}
