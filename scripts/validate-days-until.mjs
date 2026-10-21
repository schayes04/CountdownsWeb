import test from 'node:test';
import assert from 'node:assert/strict';
import { addMonths, calculateSpan } from '../assets/days-until-dates.mjs';
import { addDays, dateString, parseDate } from '../assets/anniversary-dates.mjs';

test('the published example: January 1 to December 25, 2026', () => {
  const result = calculateSpan('2026-01-01', '2026-12-25');
  assert.equal(result.direction, 1);
  assert.equal(result.days, 358);
  assert.equal(result.weeks, 51);
  assert.equal(result.extraDays, 1);
  assert.deepEqual([result.years, result.months, result.monthDays], [0, 11, 24]);
});

test('the start date counts, the end date only when included', () => {
  assert.equal(calculateSpan('2026-10-21', '2026-10-22').days, 1);
  assert.equal(calculateSpan('2026-10-21', '2026-10-22', { includeEnd: true }).days, 2);
  const same = calculateSpan('2026-10-21', '2026-10-21');
  assert.deepEqual([same.direction, same.days, same.weekdays, same.weekendDays], [0, 0, 0, 0]);
  assert.equal(calculateSpan('2026-10-21', '2026-10-21', { includeEnd: true }).days, 1);
});

test('reversed dates count the same span backwards', () => {
  const forward = calculateSpan('2025-03-01', '2026-10-21');
  const backward = calculateSpan('2026-10-21', '2025-03-01');
  assert.equal(backward.direction, -1);
  for (const key of ['days', 'weeks', 'extraDays', 'years', 'months', 'monthDays', 'weekdays', 'weekendDays']) {
    assert.equal(backward[key], forward[key], key);
  }
  assert.equal(dateString(backward.start), '2026-10-21');
});

test('daylight-saving transitions and leap days use calendar days', () => {
  assert.equal(calculateSpan('2026-03-07', '2026-03-09').days, 2);
  assert.equal(calculateSpan('2026-10-31', '2026-11-02').days, 2);
  assert.equal(calculateSpan('2024-02-28', '2024-03-01').days, 2);
  assert.equal(calculateSpan('1900-02-28', '1900-03-01').days, 1);
  assert.equal(calculateSpan('2024-01-01', '2025-01-01').days, 366);
});

test('calendar months clamp to the end of shorter months', () => {
  assert.equal(dateString(addMonths(parseDate('2026-01-31'), 1)), '2026-02-28');
  assert.equal(dateString(addMonths(parseDate('2024-01-31'), 1)), '2024-02-29');
  assert.equal(dateString(addMonths(parseDate('2026-12-15'), 2)), '2027-02-15');
  const result = calculateSpan('2026-01-31', '2026-03-01');
  assert.deepEqual([result.totalMonths, result.monthDays], [1, 1]);
  const years = calculateSpan('2020-02-29', '2026-10-21');
  assert.deepEqual([years.years, years.months, years.monthDays], [6, 7, 22]);
  assert.deepEqual(calculateSpan('2026-05-10', '2027-05-10').totalMonths, 12);
});

test('weekdays exclude the locale weekend, including Friday–Saturday weekends', () => {
  // Monday, October 19 to Monday, October 26, 2026.
  const week = calculateSpan('2026-10-19', '2026-10-26');
  assert.deepEqual([week.weekdays, week.weekendDays], [5, 2]);
  // Friday to Sunday covers Friday and Saturday only.
  const weekend = calculateSpan('2026-10-23', '2026-10-25');
  assert.deepEqual([weekend.weekdays, weekend.weekendDays], [1, 1]);
  const israel = calculateSpan('2026-10-23', '2026-10-25', { weekend: [5, 6] });
  assert.deepEqual([israel.weekdays, israel.weekendDays], [0, 2]);
  const included = calculateSpan('2026-10-23', '2026-10-25', { includeEnd: true });
  assert.deepEqual([included.weekdays, included.weekendDays], [1, 2]);
});

test('long spans match a day-by-day count', () => {
  let seed = 20261021;
  const random = () => (seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31;
  for (let run = 0; run < 200; run += 1) {
    const from = addDays(parseDate('1990-01-01'), Math.floor(random() * 20000));
    const to = addDays(from, Math.floor(random() * 4000));
    const weekend = random() < 0.5 ? [6, 7] : [5, 6];
    const result = calculateSpan(dateString(from), dateString(to), { weekend });
    let weekendDays = 0;
    for (let day = 0; day < result.days; day += 1) {
      if (weekend.includes(addDays(from, day).getUTCDay() || 7)) weekendDays += 1;
    }
    assert.equal(result.weekendDays, weekendDays);
    assert.equal(dateString(addDays(addMonths(from, result.totalMonths), result.monthDays)), dateString(to));
  }
});

test('the full supported date range and invalid input', () => {
  assert.equal(calculateSpan('0001-01-01', '9998-12-31', { includeEnd: true }).days, 3651694);
  for (const [start, end] of [['', '2026-01-01'], ['2026-02-30', '2026-03-01'], ['2026-01-01', '9999-01-01'], ['20260101', '2026-01-02']]) {
    assert.throws(() => calculateSpan(start, end), RangeError);
  }
});
