// Date-only arithmetic in UTC avoids daylight-saving and local timezone shifts.
const DAY = 86_400_000;

export function parseDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year, month, day] = value.split('-').map(Number);
  if (year < 1 || year > 9998) return null;
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(0, 0, 0, 0);
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day ? date : null;
}

export function dateString(date) {
  return date.toISOString().slice(0, 10);
}

export function localToday(now = new Date()) {
  return `${String(now.getFullYear()).padStart(4, '0')}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
}

export function daysBetween(start, end) {
  return Math.round((end - start) / DAY);
}

export function addDays(date, days) {
  return new Date(date.getTime() + days * DAY);
}

export function anniversaryInYear(start, year, leapDay = 'feb28') {
  const date = new Date(start);
  date.setUTCFullYear(year);
  // JavaScript rolls February 29 to March 1 in a non-leap year.
  if (start.getUTCMonth() === 1 && date.getUTCMonth() === 2 && leapDay === 'feb28') {
    date.setUTCDate(0);
  }
  return date;
}

export function calculateAnniversary(startValue, asOfValue, leapDay = 'feb28') {
  const start = parseDate(startValue);
  const asOf = parseDate(asOfValue);
  if (!start || !asOf) throw new RangeError('Enter valid dates between years 0001 and 9998.');
  if (asOf < start) throw new RangeError('The calculation date must be on or after your start date.');
  if (!['feb28', 'mar1'].includes(leapDay)) throw new RangeError('Choose a valid leap-day anniversary.');

  const days = daysBetween(start, asOf);
  let anniversaryNumber = Math.max(1, asOf.getUTCFullYear() - start.getUTCFullYear());
  let nextAnniversary = anniversaryInYear(start, start.getUTCFullYear() + anniversaryNumber, leapDay);
  if (nextAnniversary < asOf) {
    anniversaryNumber += 1;
    nextAnniversary = anniversaryInYear(start, start.getUTCFullYear() + anniversaryNumber, leapDay);
  }
  const nextThousand = Math.max(1000, Math.ceil(days / 1000) * 1000);
  const milestones = [...new Set([100, 500, 1000, 2000, 5000, 10000, nextThousand, nextThousand + 1000, nextThousand + 2000])]
    .filter(total => total >= days)
    .sort((a, b) => a - b)
    .map(total => ({ days: total, date: addDays(start, total), remaining: total - days }))
    .filter(milestone => milestone.date.getUTCFullYear() <= 9999)
    .slice(0, 3);

  return { start, asOf, days, weeks: Math.floor(days / 7), extraDays: days % 7,
    nextAnniversary, anniversaryNumber, anniversaryRemaining: daysBetween(asOf, nextAnniversary), milestones };
}
