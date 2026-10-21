// Calendar-day spans between two dates. The start date counts and the end date
// does not, unless includeEnd adds it. Uses the same UTC date-only arithmetic as
// the anniversary calculator, so daylight-saving changes never alter a count.
import { addDays, daysBetween, parseDate } from './anniversary-dates.mjs';

// ISO weekday numbers, 1 = Monday through 7 = Sunday, as Intl.Locale weekInfo uses.
const isoWeekday = date => date.getUTCDay() || 7;

export function addMonths(date, months) {
  const result = new Date(date);
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + months);
  const lastDay = new Date(result);
  lastDay.setUTCMonth(lastDay.getUTCMonth() + 1, 0);
  // Month ends clamp, so January 31 plus one month is the last day of February.
  result.setUTCDate(Math.min(date.getUTCDate(), lastDay.getUTCDate()));
  return result;
}

export function countWeekendDays(from, days, weekend = [6, 7]) {
  const fullWeeks = Math.floor(days / 7);
  let count = fullWeeks * weekend.length;
  for (let offset = fullWeeks * 7; offset < days; offset += 1) {
    if (weekend.includes(isoWeekday(addDays(from, offset)))) count += 1;
  }
  return count;
}

export function calculateSpan(startValue, endValue, { includeEnd = false, weekend = [6, 7] } = {}) {
  const start = parseDate(startValue);
  const end = parseDate(endValue);
  if (!start || !end) throw new RangeError('Enter valid dates between years 0001 and 9998.');

  const direction = Math.sign(daysBetween(start, end));
  const [from, to] = direction < 0 ? [end, start] : [start, end];
  // Count up to, but not including, this date.
  const until = includeEnd ? addDays(to, 1) : to;
  const days = daysBetween(from, until);

  let totalMonths = (until.getUTCFullYear() - from.getUTCFullYear()) * 12 + until.getUTCMonth() - from.getUTCMonth();
  if (addMonths(from, totalMonths) > until) totalMonths -= 1;
  const weekendDays = countWeekendDays(from, days, weekend);

  return { start, end, direction, days, weeks: Math.floor(days / 7), extraDays: days % 7,
    years: Math.floor(totalMonths / 12), months: totalMonths % 12, totalMonths,
    monthDays: daysBetween(addMonths(from, totalMonths), until), weekdays: days - weekendDays, weekendDays };
}
