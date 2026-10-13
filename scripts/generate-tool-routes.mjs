// Jekyll's GitHub Pages build needs checked-in route stubs and Intl date patterns.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const locales = JSON.parse(execFileSync('ruby', ['-ryaml', '-rjson', '-e', 'puts YAML.load_file("_data/locales.yml").to_json'], { encoding: 'utf8' }));
const holidays = JSON.parse(readFileSync('_data/holidays.json', 'utf8'));
const countryData = JSON.parse(readFileSync('_data/tool_countries.json', 'utf8'));
const check = process.argv.includes('--check');
function save(path, content) {
  if (check) { if (readFileSync(path, 'utf8') !== content) throw new Error(`Regenerate ${path}`); }
  else { mkdirSync(path.slice(0,path.lastIndexOf('/')) || '.',{recursive:true}); writeFileSync(path,content); }
}
const formats = {};
const zones = { ...countryData.zones };
for (const [zone, code] of Object.entries(countryData.zones)) {
  try { zones[new Intl.DateTimeFormat('en', {timeZone:zone}).resolvedOptions().timeZone] ??= code; } catch {}
}
save('assets/country-data.mjs', '// Generated from the public-domain IANA time zone tables; a country suggestion only.\nexport const COUNTRIES = ' + JSON.stringify(countryData.countries) + ';\nexport const zoneCountries = ' + JSON.stringify(zones) + ';\n');
for (const locale of locales) {
  const prefix = locale.folder ? `/${locale.folder}` : '';
  for (const [key, layout, extra, stylesheet] of [
    ['when-is', 'holiday-index', '', 'holiday-countdown'],
    ['anniversary-calculator', 'anniversary-calculator', '', 'anniversary-calculator'],
    ...holidays.map(h=>[`when-is/${h.slug}`, 'holiday', `holiday: ${h.slug}\n`, 'holiday-countdown'])
  ]) {
    const route = `${prefix}/${key}/`;
    const path = locale.code === 'en' && key === 'anniversary-calculator' ? 'anniversary-calculator.html' : `${route.slice(1)}index.html`;
    save(path, `---\nlayout: ${layout}\nlocale: ${locale.code}\nlocalized: true\ncanonical_key: ${key}\npermalink: ${route}\nstylesheet: /assets/${stylesheet}.css\n${extra}---\n`);
  }
  const format = {};
  for (const [style, options] of Object.entries({full:{weekday:'long',year:'numeric',month:'long',day:'numeric'},monthDay:{month:'long',day:'numeric'},weekday:{weekday:'long'},month:{month:'short'},day:{day:'numeric'},year:{year:'numeric'}})) {
    const formatter = new Intl.DateTimeFormat(locale.html_lang,{...options,calendar:'gregory',timeZone:'UTC'});
    const part=(date,type)=>formatter.formatToParts(date).find(p=>p.type===type)?.value ?? '';
    format[style]={pattern:formatter.formatToParts(new Date('2026-01-15T00:00:00Z')).map(p=>p.type==='literal'?p.value:`{${p.type}}`).join(''),
      months:Array.from({length:12},(_,i)=>part(new Date(Date.UTC(2026,i,15)),'month')),
      weekdays:Array.from({length:7},(_,i)=>part(new Date(Date.UTC(2026,0,4+i)),'weekday')),
      days:Array.from({length:31},(_,i)=>part(new Date(Date.UTC(2026,0,i+1)),'day')),
      years:Object.fromEntries(Array.from({length:102},(_,i)=>[2020+i,part(new Date(Date.UTC(2020+i,0,15)),'year')]))};
  }
  const regions = new Intl.DisplayNames(locale.html_lang,{type:'region'});
  format.countries=Object.fromEntries(countryData.countries.map(code=>[code,regions.of(code)]).sort((a,b)=>a[1].localeCompare(b[1],locale.html_lang)));
  formats[locale.code]=format;
}
save('_data/tool_formats.json',JSON.stringify(formats,null,2)+'\n');
console.log(`${check?'Checked':'Generated'} 340 tool routes and localized date formats.`);
