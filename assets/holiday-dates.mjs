// Calendar dates, not elapsed 24-hour periods: DST must not change days remaining.
const DAY = 86_400_000;
const pad = value => String(value).padStart(2, '0');

export function localDateString(now = new Date()) {
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

export function calendarDay(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new RangeError('Invalid calendar date');
  const date = new Date(`${value}T00:00:00Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new RangeError('Invalid calendar date');
  }
  return date.getTime() / DAY;
}

export function holidayDate(rule, year) {
  if (!Number.isInteger(year) || year < 1583 || year > 9998) throw new RangeError('Unsupported year');
  if (rule.type === 'easter-offset') {
    const easter = calendarDay(holidayDate({ type: 'western-easter' }, year));
    return new Date((easter + rule.offset) * DAY).toISOString().slice(0, 10);
  }
  let month = rule.month;
  let day = rule.day;
  if (rule.type === 'weekday') {
    const firstWeekday = new Date(Date.UTC(year, month - 1, 1)).getUTCDay();
    day = 1 + (rule.weekday - firstWeekday + 7) % 7 + (rule.occurrence - 1) * 7;
  } else if (rule.type === 'western-easter') {
    // Gregorian computus (Meeus/Jones/Butcher), including century corrections.
    const a = year % 19;
    const b = Math.floor(year / 100);
    const c = year % 100;
    const d = Math.floor(b / 4);
    const e = b % 4;
    const f = Math.floor((b + 8) / 25);
    const g = Math.floor((b - f + 1) / 3);
    const h = (19 * a + b - d - g + 15) % 30;
    const i = Math.floor(c / 4);
    const k = c % 4;
    const l = (32 + 2 * e + 2 * i - h - k) % 7;
    const m = Math.floor((a + 11 * h + 22 * l) / 451);
    month = Math.floor((h + l - 7 * m + 114) / 31);
    day = (h + l - 7 * m + 114) % 31 + 1;
  } else if (rule.type !== 'fixed') {
    throw new RangeError('Unknown holiday rule');
  }
  const result = `${year}-${pad(month)}-${pad(day)}`;
  calendarDay(result);
  return result;
}

export function holidayState(rule, today = localDateString()) {
  const currentDay = calendarDay(today);
  let year = Number(today.slice(0, 4));
  let date = holidayDate(rule, year);
  // Keep "today" for the whole holiday, then advance at local midnight.
  if (date < today) date = holidayDate(rule, ++year);
  const days = calendarDay(date) - currentDay;
  return { date, year, days, weeks: Math.floor(days / 7), extraDays: days % 7 };
}

export function formatHolidayDate(value, options = {}) {
  calendarDay(value);
  return new Intl.DateTimeFormat('en-US', {
    weekday: 'long', month: 'long', day: 'numeric', year: 'numeric',
    ...options, timeZone: 'UTC'
  }).format(new Date(`${value}T00:00:00Z`));
}
