// Run against a Jekyll preview. Use PLAYWRIGHT_MODULE for a bundled installation.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { holidayState, formatHolidayDate } from '../assets/holiday-dates.mjs';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const base = process.env.HOLIDAY_PREVIEW_URL || 'http://127.0.0.1:4100';
const canonicalBase = `https://countdowns-app.com${new URL(base).pathname.replace(/\/$/, '')}`;
const holidays = JSON.parse(readFileSync(new URL('../_data/holidays.json', import.meta.url), 'utf8'));
const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
let checks = 0;
try {
  for (const width of [320, 390, 1440]) {
    const context = await browser.newContext({ viewport: { width, height: 1000 }, timezoneId: 'America/New_York' });
    await context.addInitScript(() => {
      window.holidayEvents = [];
      window.addEventListener('countdowns:holiday', event => window.holidayEvents.push(event.detail));
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.clock.setFixedTime(new Date('2026-10-12T16:00:00Z'));
    for (const holiday of holidays) {
      const response = await page.goto(`${base}/when-is/${holiday.slug}/`);
      assert.equal(response.status(), 200);
      await page.locator('.holiday-live:not([hidden])').waitFor();
      const state = holidayState(holiday.rule, '2026-10-12');
      assert.equal(await page.locator('#holiday-days').innerText(), String(state.days));
      assert.equal(await page.locator('.holiday-answer time').innerText(), formatHolidayDate(state.date));
      assert.equal(await page.locator('h1').count(), 1);
      assert.equal(await page.locator('#holiday-date-rows tr').count(), 5);
      assert.equal(await page.locator('link[rel="alternate"]').count(), 35);
      assert.equal(await page.locator('link[rel="canonical"]').getAttribute('href'), `${canonicalBase}/when-is/${holiday.slug}/`);
      assert.ok((await page.title()).includes(String(state.year)));
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${holiday.slug} overflows at ${width}px`);
      await page.locator('.holiday-app').scrollIntoViewIfNeeded();
      await page.waitForFunction(() => [...document.querySelectorAll('img')].every(image => image.complete && image.naturalWidth > 0));
      assert.equal(await page.evaluate(() => window.holidayEvents.filter(item => item.event === 'holiday_view').length), 1);
      checks++;
    }
    await page.goto(`${base}/when-is/`);
    await page.locator('.holiday-card__remaining:not([hidden])').first().waitFor();
    assert.equal(await page.locator('.holiday-card').count(), 8);
    assert.equal(await page.locator('.holiday-card').first().getAttribute('data-holiday-card'), 'halloween');
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    if (width !== 320) {
      await page.screenshot({ path: `/tmp/countdowns-holidays-hub-${width}.png`, fullPage: true });
      await page.goto(`${base}/when-is/thanksgiving/`);
      await page.locator('.holiday-live:not([hidden])').waitFor();
      await page.locator('.holiday-app').scrollIntoViewIfNeeded();
      await page.waitForFunction(() => [...document.images].every(image => image.complete));
      await page.evaluate(() => scrollTo({ top: 0, behavior: 'instant' }));
      await page.waitForFunction(() => scrollY === 0);
      await page.screenshot({ path: `/tmp/countdowns-holidays-thanksgiving-${width}.png`, fullPage: true });
    }
    assert.deepEqual(errors, []);
    await context.close();
  }

  // The same instant is still Dec 31 in Los Angeles but Jan 1 in Kiritimati.
  for (const [timezoneId, expected] of [['America/Los_Angeles', '1'], ['Pacific/Kiritimati', 'Today!']]) {
    const context = await browser.newContext({ timezoneId });
    const page = await context.newPage();
    await page.clock.setFixedTime(new Date('2027-01-01T01:00:00Z'));
    await page.goto(`${base}/when-is/new-year/`);
    await page.locator('.holiday-live:not([hidden])').waitFor();
    assert.equal(await page.locator('#holiday-days').innerText(), expected);
    await context.close();
    checks++;
  }

  const context = await browser.newContext({ timezoneId: 'America/New_York' });
  await context.addInitScript(() => {
    window.holidayEvents = [];
    window.addEventListener('countdowns:holiday', event => window.holidayEvents.push(event.detail));
  });
  const page = await context.newPage();
  await page.clock.install({ time: new Date('2026-12-25T04:59:59Z') });
  await page.clock.pauseAt(new Date('2026-12-25T04:59:59Z'));
  await page.goto(`${base}/when-is/christmas/`);
  await page.locator('.holiday-live:not([hidden])').waitFor();
  assert.equal(await page.locator('#holiday-days').innerText(), '1');
  await page.clock.fastForward(2000);
  assert.equal(await page.locator('#holiday-days').innerText(), 'Today!');
  await page.clock.fastForward(86400000);
  assert.equal(await page.locator('#holiday-days').innerText(), '364');
  assert.ok((await page.title()).includes('2027'));
  assert.equal(await page.locator('.holiday-answer time').getAttribute('datetime'), '2027-12-25');
  assert.equal(await page.locator('#holiday-date-rows th').first().innerText(), '2027');
  // Capture the click without leaving the preview or opening the App Store.
  await page.evaluate(() => document.addEventListener('click', event => {
    if (event.target.closest('.app-store-badge')) event.preventDefault();
  }));
  await page.locator('.holiday-app .app-store-badge').click();
  assert.ok(await page.evaluate(() => window.holidayEvents.some(event => event.event === 'holiday_app_store_click' && event.placement === 'widget')));
  await page.keyboard.press('Tab');
  assert.ok(await page.evaluate(() => document.activeElement !== document.body));
  checks++;
  await context.close();

  const noJS = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 320, height: 900 } });
  const staticPage = await noJS.newPage();
  for (const holiday of holidays) {
    await staticPage.goto(`${base}/when-is/${holiday.slug}/`);
    assert.ok(await staticPage.locator('.holiday-answer time').isVisible());
    assert.ok(await staticPage.locator('#holiday-fallback').isVisible());
    assert.ok(!await staticPage.locator('.holiday-live').isVisible());
    assert.equal(await staticPage.locator('#holiday-date-rows tr').count(), 5);
    const scripts = await staticPage.locator('script[type="application/ld+json"]').allTextContents();
    scripts.forEach(value => JSON.parse(value));
    checks++;
  }
  await noJS.close();
  console.log(`Passed ${checks} browser scenarios: 8 holidays at 3 widths, hub, time zones, midnight/year rollover, analytics hooks, keyboard, and no-JS fallback.`);
} finally {
  await browser.close();
}
