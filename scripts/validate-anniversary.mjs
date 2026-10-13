import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateAnniversary, parseDate, dateString, localToday } from '../assets/anniversary-dates.mjs';

test('same date is day zero, not the first anniversary', () => {
  const result = calculateAnniversary('2025-06-15', '2025-06-15');
  assert.equal(result.days, 0);
  assert.equal(result.anniversaryNumber, 1);
  assert.equal(dateString(result.nextAnniversary), '2026-06-15');
  assert.deepEqual(result.milestones.map(item => item.days), [100, 500, 1000]);
});

test('a full ordinary year and the published 1,000-day example', () => {
  const result = calculateAnniversary('2025-01-01', '2026-01-01');
  assert.equal(result.days, 365);
  assert.equal(result.weeks, 52);
  assert.equal(result.extraDays, 1);
  assert.equal(result.anniversaryRemaining, 0);
  assert.equal(dateString(result.milestones.find(item => item.days === 1000).date), '2027-09-28');
});

test('daylight-saving transitions do not alter calendar-day counts', () => {
  assert.equal(calculateAnniversary('2026-03-07', '2026-03-09').days, 2);
  assert.equal(calculateAnniversary('2026-10-31', '2026-11-02').days, 2);
});

test('leap days count, but non-leap century years do not have one', () => {
  assert.equal(calculateAnniversary('2024-02-28', '2024-03-01').days, 2);
  assert.equal(calculateAnniversary('1900-02-28', '1900-03-01').days, 1);
  assert.equal(calculateAnniversary('2000-02-28', '2000-03-01').days, 2);
});

test('next anniversary advances only after the anniversary date', () => {
  assert.equal(calculateAnniversary('2020-10-12', '2026-10-11').anniversaryRemaining, 1);
  assert.equal(calculateAnniversary('2020-10-12', '2026-10-12').anniversaryRemaining, 0);
  const next = calculateAnniversary('2020-10-12', '2026-10-13');
  assert.equal(next.anniversaryNumber, 7);
  assert.equal(dateString(next.nextAnniversary), '2027-10-12');
});

test('February 29 can use either non-leap-year celebration date', () => {
  const february = calculateAnniversary('2024-02-29', '2025-02-28', 'feb28');
  const march = calculateAnniversary('2024-02-29', '2025-02-28', 'mar1');
  assert.equal(february.anniversaryRemaining, 0);
  assert.equal(march.anniversaryRemaining, 1);
  assert.equal(february.days, march.days);
  assert.equal(dateString(calculateAnniversary('2024-02-29', '2025-03-01', 'feb28').nextAnniversary), '2026-02-28');
});

test('February 29 stays February 29 in leap years, under either policy', () => {
  for (const policy of ['feb28', 'mar1']) {
    const result = calculateAnniversary('2024-02-29', '2028-02-28', policy);
    assert.equal(dateString(result.nextAnniversary), '2028-02-29');
    assert.equal(result.anniversaryRemaining, 1);
  }
});

test('month-end anniversaries never drift into another month', () => {
  assert.equal(dateString(calculateAnniversary('2020-01-31', '2026-02-01').nextAnniversary), '2027-01-31');
  assert.equal(dateString(calculateAnniversary('2020-12-31', '2026-01-01').nextAnniversary), '2026-12-31');
});

test('milestones include today and extend beyond 10,000 days', () => {
  const today = calculateAnniversary('2025-01-01', '2025-04-11');
  assert.equal(today.days, 100);
  assert.equal(today.milestones[0].remaining, 0);
  const longer = calculateAnniversary('1980-01-01', '2026-10-12');
  assert.equal(longer.milestones.length, 3);
  assert.ok(longer.milestones[0].days > 10000);
  assert.ok(longer.milestones.every(item => item.remaining >= 0));
  assert.equal(new Set(longer.milestones.map(item => item.days)).size, 3);
});

test('reversed, absent, and impossible dates are rejected', () => {
  for (const value of ['', 'abc', '2025-02-29', '2025-04-31', '2026-13-01', '2026-00-01', '2026-01-00', '10000-01-01']) {
    assert.equal(parseDate(value), null);
    assert.throws(() => calculateAnniversary(value, '2026-10-12'), RangeError);
  }
  assert.throws(() => calculateAnniversary('2026-10-13', '2026-10-12'), /on or after/);
  assert.throws(() => calculateAnniversary('2026-01-01', ''), RangeError);
  assert.throws(() => calculateAnniversary('2026-01-01', '2026-02-01', 'unknown'), RangeError);
});

test('early years and upper input boundary are handled without Date year coercion', () => {
  assert.equal(dateString(parseDate('0001-01-01')), '0001-01-01');
  assert.equal(calculateAnniversary('0099-12-31', '0100-01-01').days, 1);
  const result = calculateAnniversary('9998-01-01', '9998-12-31');
  assert.equal(dateString(result.nextAnniversary), '9999-01-01');
  assert.ok(result.milestones.every(item => item.date.getUTCFullYear() <= 9999));
});

test('today uses the visitor’s local calendar date', () => {
  const original = process.env.TZ;
  try {
    process.env.TZ = 'America/Los_Angeles';
    assert.equal(localToday(new Date('2026-10-12T01:00:00Z')), '2026-10-11');
    process.env.TZ = 'Asia/Tokyo';
    assert.equal(localToday(new Date('2026-10-12T23:00:00Z')), '2026-10-13');
  } finally {
    if (original === undefined) delete process.env.TZ;
    else process.env.TZ = original;
  }
});
