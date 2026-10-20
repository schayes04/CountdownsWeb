import { localDateString, holidayDate, holidayState } from './holiday-dates.mjs';
import { interpolate, toolFormatters } from './tool-i18n.mjs';
import { COUNTRIES, suggestCountry, holidayObservance, countriesForHoliday } from './holiday-country.mjs';

const config = JSON.parse(document.getElementById('tool-data').textContent);
const copy = config.strings;
const fmt = toolFormatters(config.locale);
const data = document.getElementById('holiday-data');
const holiday = data ? JSON.parse(data.textContent) : null;
const countrySelect = document.getElementById('holiday-country');
const storageKey = 'countdowns.holidayCountry';
let country = '';
let manual = false;
try {
  const saved = localStorage.getItem(storageKey);
  if (saved !== null && (saved === '' || COUNTRIES.includes(saved))) { country = saved; manual = true; }
} catch { /* The selector also works with storage disabled. */ }
// Regional English pages default to their own country so the page matches its crawlable HTML.
if (!manual) country = config.holidayCountry || suggestCountry(navigator.languages, Intl.DateTimeFormat().resolvedOptions().timeZone);
let renderedDay;
let renderedZone;
let timer;

function measure(event, placement) {
  window.dispatchEvent(new CustomEvent('countdowns:holiday', { detail: { event, holiday: holiday?.slug ?? 'index', placement } }));
}
function observance(slug, baseRule, date) {
  const result = holidayObservance(slug, baseRule, country);
  const labels = { thanksgiving: 'thanksgiving_rule', 'mothers-day': 'mother_rule', 'fathers-day': 'father_rule' };
  if (baseRule.type === 'fixed') return { ...result, scope: fmt.date(date, { weekday:undefined,year:undefined }), label: interpolate(copy.fixed_rule, { date:fmt.date(date,{weekday:undefined,year:undefined}) }) };
  if (baseRule.type === 'western-easter') return { ...result, scope:copy.western_easter, label:copy.easter_rule };
  return { ...result, scope:config.countries[result.country], label:copy[result.label || labels[slug]] };
}
function renderHoliday(today) {
  const rule = holidayObservance(holiday.slug, holiday.rule, country).rule;
  const state = holidayState(rule, today);
  const selected = observance(holiday.slug, holiday.rule, state.date);
  const name = config.holidays[holiday.slug].name;
  const dateText = fmt.date(state.date);
  // Years should not use thousands grouping.
  const yearText = new Intl.NumberFormat(config.locale, {useGrouping:false}).format(state.year);
  document.querySelector('[data-holiday-heading]').textContent = interpolate(copy.holiday_title, {holiday:name,year:yearText});
  document.querySelectorAll('[data-holiday-date]').forEach(node => { node.dateTime=state.date; node.textContent=dateText; });
  document.querySelector('[data-holiday-month]').textContent = fmt.date(state.date,{weekday:undefined,year:undefined,day:undefined,month:'short'});
  document.querySelector('[data-holiday-day]').textContent = fmt.number(Number(state.date.slice(-2)));
  document.querySelector('[data-holiday-scope]').textContent=selected.scope;
  document.getElementById('holiday-days').textContent = state.days===0 ? copy.today : fmt.number(state.days);
  document.getElementById('holiday-unit').textContent = state.days===0 ? name : copy.remaining_days;
  document.getElementById('holiday-weeks').textContent = state.days===0 ? '' : interpolate(copy.remaining,{duration:fmt.list([fmt.unit(state.weeks,'week'),...(state.extraDays ? [fmt.unit(state.extraDays,'day')] : [])])});
  document.getElementById('holiday-clock-note').textContent = interpolate(copy.calendar_days,{zone:Intl.DateTimeFormat().resolvedOptions().timeZone.replaceAll('_',' ')});
  document.getElementById('holiday-fallback').hidden=true;
  document.querySelector('.holiday-live').hidden=false;
  document.getElementById('holiday-table-caption').textContent = rule.type==='fixed' ? selected.label : `${selected.scope} · ${selected.label}`;
  const regional = Boolean(selected.source);
  const holidayCopy = config.holidays[holiday.slug];
  document.querySelector('[data-holiday-intro]').textContent = regional ? copy.hub_intro : holidayCopy.intro;
  document.getElementById('holiday-explanation-heading').textContent = regional || config.locale.split('-')[0] !== 'en' ? selected.label : holidayCopy.explanation_title;
  document.getElementById('holiday-default-explanation').hidden=regional;
  const explanation = document.getElementById('holiday-regional-explanation');
  explanation.hidden=!regional;
  explanation.textContent=interpolate(copy.regional_about,{scope:`${selected.scope} · ${selected.label}`});
  const source = document.getElementById('holiday-source');
  source.href=selected.source || holiday.source_url;
  source.textContent=selected.sourceName || holiday.source_label;

  const rows=Array.from({length:5},(_,index)=>{
    const date=holidayDate(rule,state.year+index);
    const row=document.createElement('tr');
    const year=document.createElement('th');year.scope='row';year.textContent=new Intl.NumberFormat(config.locale,{useGrouping:false}).format(state.year+index);
    const cell=document.createElement('td');const time=document.createElement('time');time.dateTime=date;
    const weekday=fmt.date(date,{year:undefined,month:undefined,day:undefined});
    time.textContent=rule.type==='fixed' ? weekday : fmt.date(date,{weekday:undefined,year:undefined});
    cell.append(time);row.append(year,cell);
    if(rule.type!=='fixed'){const day=document.createElement('td');day.textContent=weekday;row.append(day);}
    return row;
  });
  document.getElementById('holiday-date-rows').replaceChildren(...rows);
  const title=`${interpolate(copy.holiday_title,{holiday:name,year:yearText})} ${copy.title_suffix} | ${config.appName}`;
  const description=interpolate(copy.holiday_description,{holiday:name,date:dateText});
  document.title=title;
  for(const selector of ['meta[property="og:title"]','meta[name="twitter:title"]']) document.querySelector(selector)?.setAttribute('content',title);
  for(const selector of ['meta[name="description"]','meta[property="og:description"]','meta[name="twitter:description"]']) document.querySelector(selector)?.setAttribute('content',description);
}
function renderHub(today) {
  const grid=document.getElementById('holiday-card-grid');
  const cards=[...grid.querySelectorAll('[data-holiday-card]')];
  for(const card of cards){
    const slug=card.dataset.holidayCard;
    const baseRule=JSON.parse(card.dataset.rule);
    const result=holidayState(holidayObservance(slug,baseRule,country).rule,today);
    card.dataset.nextDate=result.date;
    const date=card.querySelector('time');date.dateTime=result.date;date.textContent=fmt.date(result.date);
    card.querySelector('.holiday-card__scope').textContent=observance(slug,baseRule,result.date).scope;
    const count=card.querySelector('.holiday-card__remaining');count.textContent=result.days===0 ? copy.today : interpolate(copy.remaining,{duration:fmt.unit(result.days,'day')});count.hidden=false;
  }
  cards.sort((a,b)=>a.dataset.nextDate.localeCompare(b.dataset.nextDate));grid.append(...cards);
}
function refresh(force=false) {
  clearTimeout(timer);
  const now=new Date();const today=localDateString(now);const zone=Intl.DateTimeFormat().resolvedOptions().timeZone;
  if(force || today!==renderedDay || zone!==renderedZone){
    if(holiday)renderHoliday(today);else renderHub(today);
    renderedDay=today;renderedZone=zone;
  }
  const midnight=new Date(now.getFullYear(),now.getMonth(),now.getDate()+1);
  timer=setTimeout(()=>refresh(),Math.min(60_000,midnight-now+50));
}
const availableCountries = countriesForHoliday(holiday?.slug);
for (const [code, name] of Object.entries(config.countries)) {
  if (!availableCountries.includes(code)) continue;
  const option = document.createElement('option');
  option.value = code;
  option.textContent = name;
  countrySelect.append(option);
}
// Preserve the visitor's country across pages, while defaulting the picker
// to the US whenever that country has no supported option here.
countrySelect.value = availableCountries.includes(country) ? country : 'US';
countrySelect.closest('.holiday-country').hidden = availableCountries.length === 0;
const hint=document.getElementById('holiday-country-hint');
hint.hidden = manual || Boolean(config.holidayCountry) || !availableCountries.includes(country);
if (hint.hidden) countrySelect.removeAttribute('aria-describedby');
countrySelect.addEventListener('change',()=>{
  country=availableCountries.includes(countrySelect.value) ? countrySelect.value : 'US';
  try{localStorage.setItem(storageKey,country);}catch{ /* Selection still works without storage. */ }
  hint.hidden = true;
  countrySelect.removeAttribute('aria-describedby');
  refresh(true);
});
document.addEventListener('click',event=>{const link=event.target.closest('a[href]');if(link && new URL(link.href).hostname==='apps.apple.com')measure('holiday_app_store_click',link.closest('[data-holiday-placement]')?.dataset.holidayPlacement ?? (link.closest('header')?'header':'page'));});
document.addEventListener('visibilitychange',()=>{if(document.hidden)clearTimeout(timer);else refresh();});
window.addEventListener('pageshow',()=>refresh());
refresh();measure('holiday_view',holiday?'detail':'index');
