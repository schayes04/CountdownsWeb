import { interpolate, toolFormatters } from './tool-i18n.mjs';
import { calculateAnniversary, localToday, parseDate } from './anniversary-dates.mjs';

const form = document.querySelector('#anniversary-form');
const startInput = form.elements.start;
const asOfInput = form.elements.asof;
const leapInput = form.elements.leapday;
const error = document.querySelector('#calculator-error');
const results = document.querySelector('#calculator-results');
const empty = document.querySelector('#calculator-empty');
const { locale, strings: copy } = JSON.parse(document.getElementById('tool-data').textContent);
const fmt = toolFormatters(locale);
const dates = { format: date => fmt.date(date, { weekday: undefined }) };
const numbers = { format: fmt.number };

const plural = (value, unit) => fmt.unit(value, unit);
const countdown = value => value === 0 ? copy.today : interpolate(copy.remaining, { duration: plural(value, 'day') });
const show = (id, text) => { document.getElementById(id).textContent = text; };

function updateLeapChoice() {
  const start = parseDate(startInput.value);
  document.querySelector('#leap-day-field').hidden = !(start && start.getUTCMonth() === 1 && start.getUTCDate() === 29);
}

asOfInput.value = localToday();
document.querySelector('#use-today').addEventListener('click', () => {
  asOfInput.value = localToday();
  clearResult();
});

function clearResult() {
  results.hidden = true;
  empty.hidden = false;
  error.hidden = true;
  for (const input of [startInput, asOfInput]) input.removeAttribute('aria-invalid');
  updateLeapChoice();
}

form.addEventListener('input', clearResult);
form.addEventListener('change', clearResult);
form.addEventListener('submit', event => {
  event.preventDefault();
  clearResult();
  if (!startInput.value || !parseDate(startInput.value)) {
    error.textContent = copy.error_start;
    startInput.setAttribute('aria-invalid', 'true');
    error.hidden = false;
    startInput.focus();
    return;
  }
  let result;
  try {
    result = calculateAnniversary(startInput.value, asOfInput.value, leapInput.value);
  } catch (problem) {
    error.textContent = asOfInput.value && parseDate(asOfInput.value) ? copy.error_order : copy.error_dates;
    asOfInput.setAttribute('aria-invalid', 'true');
    error.hidden = false;
    asOfInput.focus();
    return;
  }
  show('total-days', numbers.format(result.days));
  show('day-unit', copy.days_together);
  show('total-weeks', fmt.list([plural(result.weeks, 'week'), plural(result.extraDays, 'day')]));
  show('date-range', `${dates.format(result.start)} – ${dates.format(result.asOf)}`);
  show('anniversary-label', interpolate(copy.years_together, { duration: plural(result.anniversaryNumber, 'year') }));
  show('anniversary-date', dates.format(result.nextAnniversary));
  show('anniversary-countdown', countdown(result.anniversaryRemaining));
  const milestones = document.querySelector('#milestone-list');
  milestones.replaceChildren();
  for (const milestone of result.milestones) {
    const item = document.createElement('li');
    const label = document.createElement('strong');
    label.textContent = plural(milestone.days, 'day');
    const date = document.createElement('span');
    date.textContent = dates.format(milestone.date);
    const remaining = document.createElement('span');
    remaining.className = 'calculator-milestone__remaining';
    remaining.textContent = countdown(milestone.remaining);
    item.append(label, date, remaining);
    milestones.append(item);
  }
  empty.hidden = true;
  results.hidden = false;
  document.querySelector('#result-heading').focus({ preventScroll: true });
  results.scrollIntoView({ behavior: 'instant', block: 'nearest' });
});

// Enable the form only after the calculator has loaded successfully.
document.querySelector('#calculator-fields').disabled = false;
document.querySelector('#calculator-loading').hidden = true;
