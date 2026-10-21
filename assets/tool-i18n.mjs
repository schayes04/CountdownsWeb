export const interpolate = (text, values = {}) => text.replace(/\{(\w+)\}/g, (match, key) => values[key] ?? match);
// ICU calls a day "døgn"/"dygn"/"doba" (a 24-hour period) in Norwegian, Swedish,
// and Polish; people count calendar days as "dager"/"dagar"/"dni".
const DAY_WORDS = { nb: ['dag', 'dager'], pl: ['dzień', 'dni'], sv: ['dag', 'dagar'] };
export function toolFormatters(locale) {
  const options = { calendar: 'gregory', timeZone: 'UTC' };
  const number = value => new Intl.NumberFormat(locale).format(value);
  const dayWords = DAY_WORDS[new Intl.Locale(locale).language];
  return {
    number,
    date: (value, style = {}) => new Intl.DateTimeFormat(locale, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric', ...style, ...options }).format(value instanceof Date ? value : new Date(`${value}T00:00:00Z`)),
    unit: (value, unit) => unit === 'day' && dayWords
      ? `${number(value)} ${dayWords[value === 1 ? 0 : 1]}`
      : new Intl.NumberFormat(locale, { style: 'unit', unit, unitDisplay: 'long' }).format(value),
    list: values => new Intl.ListFormat(locale, { type: 'conjunction' }).format(values)
  };
}
