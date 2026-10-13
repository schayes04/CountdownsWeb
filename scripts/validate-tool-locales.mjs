import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { suggestCountry, holidayObservance, countriesForHoliday } from '../assets/holiday-country.mjs';
import { holidayDate, holidayState } from '../assets/holiday-dates.mjs';
import { toolFormatters, interpolate } from '../assets/tool-i18n.mjs';

const read = path => JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'));
const english = read('_data/tools/en.json');
const formats = read('_data/tool_formats.json');
const holidays = read('_data/holidays.json');
const rules = Object.fromEntries(holidays.map(h => [h.slug, h.rule]));
const tokens = value => [...value.matchAll(/\{(\w+)\}/g)].map(match => match[1]).sort();

test('all 34 tool catalogs include every translated string, placeholder, and holiday', () => {
  const files = readdirSync(new URL('../_data/tools/', import.meta.url)).filter(file => file.endsWith('.json'));
  assert.equal(files.length, 34);
  assert.deepEqual(files.map(file => file.slice(0, -5)).sort(), Object.keys(formats).sort());
  for (const file of files) {
    const catalog = read(`_data/tools/${file}`);
    assert.deepEqual(Object.keys(catalog.strings).sort(), Object.keys(english.strings).sort(), file);
    for (const [key, value] of Object.entries(catalog.strings)) {
      assert.ok(typeof value === 'string' && value.trim(), `${file}: ${key}`);
      assert.deepEqual(tokens(value), tokens(english.strings[key]), `${file}: ${key} placeholders`);
    }
    assert.deepEqual(Object.keys(catalog.holidays).sort(), Object.keys(rules).sort(), file);
    for (const [slug, value] of Object.entries(catalog.holidays)) {
      assert.deepEqual(Object.keys(value).sort(), Object.keys(english.holidays[slug]).sort(), `${file}: ${slug}`);
      for (const key of ['name','date_name','intro','explanation','scope_note']) assert.ok(value[key].trim(), `${file}: ${slug}.${key}`);
    }
  }
});

test('browser country suggestions use a known time zone, then explicit locale region', () => {
  assert.equal(suggestCountry(['en-US'], 'America/Toronto'), 'CA');
  assert.equal(suggestCountry(['en-US'], 'Europe/London'), 'GB');
  assert.equal(suggestCountry(['en'], 'Australia/Sydney'), 'AU');
  assert.equal(suggestCountry(['en'], 'Pacific/Auckland'), 'NZ');
  assert.equal(suggestCountry(['en-US'], 'Asia/Tokyo'), 'JP');
  assert.equal(suggestCountry(['en-US'], 'America/New_York'), 'US');
  assert.equal(suggestCountry(['fr-CA'], 'UTC'), 'CA');
  assert.equal(suggestCountry(['invalid_locale', 'en-GB'], ''), 'GB');
  assert.equal(suggestCountry(['pt-BR'], 'Etc/UTC'), 'BR');
  assert.equal(suggestCountry(['zh-Hant-TW'], ''), 'TW');
});

test('unknown locations never infer a country from a language alone', () => {
  assert.equal(suggestCountry(['en'], 'UTC'), '');
  assert.equal(suggestCountry(['es'], ''), '');
  assert.equal(suggestCountry(['en-US'], 'Unknown/Zone'), '');
  assert.equal(suggestCountry(['en-ZZ'], ''), '');
  assert.equal(suggestCountry([], ''), '');
});

test('country pickers offer only supported differences for the current page', () => {
  assert.deepEqual(countriesForHoliday(), ['US', 'CA', 'GB', 'AU', 'NZ']);
  assert.deepEqual(countriesForHoliday('thanksgiving'), ['US', 'CA']);
  assert.deepEqual(countriesForHoliday('mothers-day'), ['US', 'GB']);
  assert.deepEqual(countriesForHoliday('fathers-day'), ['US', 'AU', 'NZ']);
  for (const slug of ['christmas', 'halloween', 'new-year', 'easter', 'valentines-day']) {
    assert.deepEqual(countriesForHoliday(slug), []);
  }
});

test('regional holidays follow their published rules and roll over after the day', () => {
  const cases = [
    ['thanksgiving','CA','2026-10-12','2027-10-11'],
    ['mothers-day','GB','2026-03-15','2027-03-07'],
    ['fathers-day','AU','2026-09-06','2027-09-05'],
    ['fathers-day','NZ','2026-09-06','2027-09-05']
  ];
  for (const [slug, country, date, nextDate] of cases) {
    const observance = holidayObservance(slug, rules[slug], country);
    assert.equal(observance.country, country);
    assert.ok(observance.source.startsWith('https://'));
    assert.equal(holidayDate(observance.rule, 2026), date);
    assert.equal(holidayState(observance.rule, date).days, 0);
    const tomorrow = new Date(`${date}T00:00:00Z`); tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    assert.equal(holidayState(observance.rule, tomorrow.toISOString().slice(0,10)).date, nextDate);
  }
  assert.equal(holidayDate(holidayObservance('mothers-day', rules['mothers-day'], 'GB').rule, 2024), '2024-03-10');
});

test('unsupported regional rules preserve the named US observance and fixed dates', () => {
  for (const country of ['FR','TH','JP','DE','','XX']) {
    for (const slug of ['thanksgiving','mothers-day','fathers-day']) {
      const observance = holidayObservance(slug, rules[slug], country);
      assert.equal(observance.country, 'US');
      assert.deepEqual(observance.rule, rules[slug]);
    }
    assert.deepEqual(holidayObservance('christmas', rules.christmas, country).rule, rules.christmas);
    assert.deepEqual(holidayObservance('easter', rules.easter, country).rule, rules.easter);
  }
});

test('date formatting keeps Gregorian years in every locale and localizes units', () => {
  for (const locale of Object.keys(formats)) {
    const fmt = toolFormatters(locale);
    const text = fmt.date('2026-12-25');
    assert.ok(text && !text.includes('Invalid'), locale);
    assert.equal(new Intl.DateTimeFormat(locale, { calendar:'gregory' }).resolvedOptions().calendar, 'gregory');
    assert.ok(fmt.unit(1, 'day'));
    assert.ok(fmt.list([fmt.unit(2, 'week'), fmt.unit(3, 'day')]));
    for (const [style, format] of Object.entries(formats[locale])) {
      if (style === 'countries') continue;
      assert.ok(!tokens(format.pattern).some(key => !['year','month','day','weekday'].includes(key)), `${locale}: ${style}`);
      assert.equal(format.years['2026'] === undefined, false);
    }
  }
  assert.equal(toolFormatters('fr').unit(1, 'day'), '1\u00a0jour');
  assert.equal(toolFormatters('ja').date('2026-12-25', {weekday:undefined}), '2026年12月25日');
  assert.equal(interpolate('{holiday}: {date}', {holiday:'Noël',date:'25 décembre'}), 'Noël: 25 décembre');
});
