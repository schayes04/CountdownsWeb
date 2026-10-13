import { COUNTRIES, zoneCountries } from './country-data.mjs';
export { COUNTRIES };
export function suggestCountry(languages = [], timeZone = '') {
  if (zoneCountries[timeZone]) return zoneCountries[timeZone];
  if (timeZone && !['UTC','Etc/UTC','Etc/GMT','GMT'].includes(timeZone)) return '';
  for (const language of languages) {
    try { const region = new Intl.Locale(language).region; if (COUNTRIES.includes(region)) return region; } catch { /* Invalid browser locale. */ }
  }
  return '';
}
export const regionalRules = {
  CA: { thanksgiving: { rule: { type:'weekday',month:10,weekday:1,occurrence:2 }, label:'canada_thanksgiving_rule', source:'https://www.canada.ca/en/library-archives/services/public/visit/holiday-closures.html', sourceName:'Library and Archives Canada' } },
  GB: { 'mothers-day': { rule: { type:'easter-offset',offset:-21 }, label:'uk_mother_rule', source:'https://www.churchofengland.org/media/stories-and-features/mothering-sunday-what-are-its-origins-church', sourceName:'Church of England' } },
  AU: { 'fathers-day': { rule: { type:'weekday',month:9,weekday:0,occurrence:1 }, label:'australia_father_rule', source:'https://www.islhd.health.nsw.gov.au/sites/default/files/Health_Promotion/Healthy_schools/2026_Schools_Calendar.pdf', sourceName:'NSW Health' } },
  NZ: { 'fathers-day': { rule: { type:'weekday',month:9,weekday:0,occurrence:1 }, label:'australia_father_rule', source:'https://collections.tepapa.govt.nz/object/1663302', sourceName:'Museum of New Zealand Te Papa Tongarewa' } }
};
// Only offer countries whose supported rules can change the displayed dates.
export function countriesForHoliday(slug) {
  const variants = Object.keys(regionalRules).filter(country => !slug || regionalRules[country][slug]);
  return variants.length ? ['US', ...variants] : [];
}
export function holidayObservance(slug, baseRule, country) {
  const regional = regionalRules[country]?.[slug];
  return regional ? { ...regional, country } : { rule: baseRule, country: baseRule.type === 'weekday' ? 'US' : '' };
}
