export const interpolate = (text, values = {}) => text.replace(/\{(\w+)\}/g, (match, key) => values[key] ?? match);
export function toolFormatters(locale) {
  const options = { calendar: 'gregory', timeZone: 'UTC' };
  return {
    number: value => new Intl.NumberFormat(locale).format(value),
    date: (value, style = {}) => new Intl.DateTimeFormat(locale, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric', ...style, ...options }).format(value instanceof Date ? value : new Date(`${value}T00:00:00Z`)),
    unit: (value, unit) => new Intl.NumberFormat(locale, { style: 'unit', unit, unitDisplay: 'long' }).format(value),
    list: values => new Intl.ListFormat(locale, { type: 'conjunction' }).format(values)
  };
}
