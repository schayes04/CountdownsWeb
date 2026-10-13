import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { calendarDay, holidayDate, holidayState, localDateString, formatHolidayDate } from '../assets/holiday-dates.mjs';

const holidays = JSON.parse(readFileSync(new URL('../_data/holidays.json', import.meta.url), 'utf8'));
const rules = Object.fromEntries(holidays.map(item => [item.slug, item.rule]));
const dates = JSON.parse(readFileSync(new URL('../_data/holiday_dates.json', import.meta.url), 'utf8'));

test('2026 and 2027 dates match published calendars', () => {
  const expected = {
    christmas: ['2026-12-25', '2027-12-25'],
    halloween: ['2026-10-31', '2027-10-31'],
    'new-year': ['2026-01-01', '2027-01-01'],
    thanksgiving: ['2026-11-26', '2027-11-25'],
    easter: ['2026-04-05', '2027-03-28'],
    'valentines-day': ['2026-02-14', '2027-02-14'],
    'mothers-day': ['2026-05-10', '2027-05-09'],
    'fathers-day': ['2026-06-21', '2027-06-20']
  };
  assert.deepEqual(Object.keys(rules).sort(), Object.keys(expected).sort());
  for (const [slug, values] of Object.entries(expected)) {
    values.forEach((value, index) => assert.equal(holidayDate(rules[slug], 2026 + index), value, slug));
  }
});

test('Gregorian Easter matches Census reference years, including exceptional corrections', () => {
  // https://www.census.gov/data/software/x13as/genhol/easter-dates.html
  for (const date of ['1818-03-22', '1943-04-25', '1954-04-18', '1981-04-19', '2000-04-23', '2024-03-31', '2025-04-20', '2028-04-16', '2029-04-01', '2030-04-21', '2038-04-25', '2049-04-18', '2076-04-19', '2099-04-12']) {
    assert.equal(holidayDate(rules.easter, Number(date.slice(0, 4))), date);
  }
});

test('Thanksgiving is the fourth Thursday even in a five-Thursday November', () => {
  assert.equal(holidayDate(rules.thanksgiving, 2029), '2029-11-22');
});

test('holidays remain today until the following local date', () => {
  for (const holiday of holidays) {
    const date = holidayDate(holiday.rule, 2026);
    const previous = new Date((calendarDay(date) - 1) * 86400000).toISOString().slice(0, 10);
    const following = new Date((calendarDay(date) + 1) * 86400000).toISOString().slice(0, 10);
    assert.equal(holidayState(holiday.rule, previous).days, 1);
    assert.equal(holidayState(holiday.rule, date).days, 0);
    assert.equal(holidayState(holiday.rule, following).date, holidayDate(holiday.rule, 2027));
  }
});

test('New Year rolls forward across the year boundary', () => {
  assert.deepEqual(holidayState(rules['new-year'], '2026-12-31'), { date: '2027-01-01', year: 2027, days: 1, weeks: 0, extraDays: 1 });
  assert.equal(holidayState(rules['new-year'], '2027-01-01').days, 0);
  assert.equal(holidayState(rules['new-year'], '2027-01-02').date, '2028-01-01');
});

test('leap years and daylight-saving transitions count full calendar dates', () => {
  assert.equal(calendarDay('2026-03-09') - calendarDay('2026-03-07'), 2);
  assert.equal(calendarDay('2026-11-02') - calendarDay('2026-10-31'), 2);
  assert.equal(calendarDay('2028-03-01') - calendarDay('2028-02-28'), 2);
  assert.equal(calendarDay('2100-03-01') - calendarDay('2100-02-28'), 1);
  const remaining = holidayState(rules.christmas, '2026-10-12');
  assert.equal(remaining.days, 74);
  assert.equal(remaining.weeks, 10);
  assert.equal(remaining.extraDays, 4);
});

test('local date extraction and UTC date formatting do not shift the holiday', () => {
  assert.equal(localDateString(new Date(2026, 11, 31, 23, 59)), '2026-12-31');
  assert.equal(formatHolidayDate('2026-12-25'), 'Friday, December 25, 2026');
});

test('invalid date inputs and unknown rules are rejected', () => {
  for (const date of ['', '2026-02-30', '2026-02-29', '2026-13-01', 'not-a-date']) {
    assert.throws(() => holidayState(rules.christmas, date), RangeError);
  }
  assert.throws(() => holidayDate({ type: 'unknown' }, 2026), RangeError);
  assert.throws(() => holidayDate(rules.easter, NaN), RangeError);
});

test('static Jekyll dates and browser rules agree for the full supported table', () => {
  for (const holiday of holidays) {
    assert.equal(dates[holiday.slug].length, 101);
    for (const [index, date] of dates[holiday.slug].entries()) {
      assert.equal(date, holidayDate(holiday.rule, 2020 + index));
      assert.equal(holidayState(holiday.rule, date).days, 0);
    }
  }
});
