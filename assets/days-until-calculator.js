import { interpolate, toolFormatters } from './tool-i18n.mjs';
import { localToday, parseDate } from './anniversary-dates.mjs';
import { calculateSpan } from './days-until-dates.mjs';
import { holidayState } from './holiday-dates.mjs';

const form = document.querySelector('#days-form');
const startInput = form.elements.start;
const endInput = form.elements.end;
const includeEndInput = form.elements.include_end;
const error = document.querySelector('#calculator-error');
const results = document.querySelector('#calculator-results');
const empty = document.querySelector('#calculator-empty');
const { locale, strings: copy } = JSON.parse(document.getElementById('tool-data').textContent);
const fmt = toolFormatters(locale);
const formatDate = date => fmt.date(date);
const show = (id, text) => { document.getElementById(id).textContent = text; };

// The weekend follows the page language's region (Friday–Saturday for Hebrew
// and Arabic, Sunday for Hindi). Browsers without Intl week data use the same
// CLDR weekends, or Saturday–Sunday.
const FALLBACK_WEEKENDS = { ar: [5, 6], he: [5, 6], hi: [7] };
function localeWeekend() {
  try {
    const info = new Intl.Locale(locale);
    const week = info.getWeekInfo?.() ?? info.weekInfo;
    if (week?.weekend?.length) return week.weekend;
    return FALLBACK_WEEKENDS[info.language] ?? [6, 7];
  } catch {}
  return [6, 7];
}
const weekend = localeWeekend();
const weekdayName = new Intl.DateTimeFormat(locale, { weekday: 'long', timeZone: 'UTC' });
// January 1, 2024 was a Monday, so day N of that month has ISO weekday N.
const weekendNames = fmt.list(weekend.map(day => weekdayName.format(new Date(Date.UTC(2024, 0, day)))));

// Show the number large and the rest of the phrase ("days", "de zile", "天") beside it.
function dayParts(days) {
  const number = fmt.number(days);
  return { number, unit: fmt.unit(days, 'day').replace(number, '').trim() };
}

function units(values) {
  const parts = values.filter(([value]) => value > 0).map(([value, unit]) => fmt.unit(value, unit));
  return parts.length ? fmt.list(parts) : fmt.unit(0, 'day');
}

function clearResult() {
  results.hidden = true;
  empty.hidden = false;
  error.hidden = true;
  for (const input of [startInput, endInput]) input.removeAttribute('aria-invalid');
}

function render(result) {
  const { number, unit } = dayParts(result.days);
  show('total-days', number);
  show('day-unit', unit);
  const duration = fmt.unit(result.days, 'day');
  const today = localToday();
  let sentence;
  if (result.direction === 0) sentence = copy.days_same;
  else if (startInput.value === today) sentence = interpolate(result.direction > 0 ? copy.days_until : copy.days_since, { duration, date: formatDate(result.end) });
  else sentence = interpolate(copy.days_between, { duration, start: formatDate(result.start), end: formatDate(result.end) });
  show('days-sentence', sentence);
  show('days-weeks', units([[result.weeks, 'week'], [result.extraDays, 'day']]));
  document.querySelector('#days-months-row').hidden = result.totalMonths === 0;
  show('days-months', units([[result.years, 'year'], [result.months, 'month'], [result.monthDays, 'day']]));
  show('days-weekdays', fmt.number(result.weekdays));
  show('days-weekend-label', interpolate(copy.days_label_weekend, { days: weekendNames }));
  show('days-weekend', fmt.number(result.weekendDays));
  empty.hidden = true;
  results.hidden = false;
}

function calculate() {
  return calculateSpan(startInput.value, endInput.value, { includeEnd: includeEndInput.checked, weekend });
}

function revealResult() {
  document.querySelector('#result-heading').focus({ preventScroll: true });
  results.scrollIntoView({ behavior: 'instant', block: 'nearest' });
}

startInput.value = localToday();
document.querySelector('#use-today').addEventListener('click', () => {
  startInput.value = localToday();
  form.dispatchEvent(new Event('change'));
});

// Results follow the inputs as soon as both dates are valid; errors wait for submit.
function update() {
  clearResult();
  if (parseDate(startInput.value) && parseDate(endInput.value)) render(calculate());
}
form.addEventListener('input', update);
form.addEventListener('change', update);

for (const button of document.querySelectorAll('.days-quick button')) {
  button.addEventListener('click', () => {
    const today = localToday();
    startInput.value = today;
    endInput.value = holidayState(JSON.parse(button.dataset.rule), today).date;
    update();
    revealResult();
  });
}

form.addEventListener('submit', event => {
  event.preventDefault();
  clearResult();
  for (const [input, message] of [[startInput, copy.days_error_start], [endInput, copy.days_error_end]]) {
    if (parseDate(input.value)) continue;
    error.textContent = input.value ? copy.error_dates : message;
    input.setAttribute('aria-invalid', 'true');
    error.hidden = false;
    input.focus();
    return;
  }
  render(calculate());
  revealResult();
});

// Enable the form only after the calculator has loaded successfully.
document.querySelector('#calculator-fields').disabled = false;
document.querySelector('#calculator-loading').hidden = true;
