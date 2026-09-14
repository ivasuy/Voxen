async (page) => {
  const failures = [];
  const check = (condition, message) => { if (!condition) failures.push(message); };
  await page.emulateMedia({ colorScheme: 'light', reducedMotion: 'reduce' });
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto('http://127.0.0.1:4175');
  await page.getByRole('heading', { name: 'Speak intent, not text.' }).waitFor();
  await page.evaluate(() => document.fonts.ready);
  // Load off-screen screenshots before full-page visual captures (normal users retain lazy loading).
  await page.locator('.app-shot img').evaluateAll(images => Promise.all(images.map(image => { image.loading = 'eager'; return image.decode(); })));
  check(await page.locator('header nav a').allTextContents().then(labels => labels.join(',') === 'Context,Writing,History,Setup'), 'Four single-word nav items');
  check(await page.getByRole('button', { name: 'Switch color theme' }).count() === 0, 'No light theme control');
  check(await page.getByRole('button', { name: /status preview/i }).count() === 0, 'No separate status controls');
  check(await page.locator('.status-listening').evaluate(el => getComputedStyle(el).opacity === '1'), 'Reduced motion keeps one clear status');
  for (const [width, height] of [[1440, 1000], [2560, 1440], [768, 1024], [390, 844], [320, 740]]) {
    await page.setViewportSize({ width, height });
    const layout = await page.evaluate(() => ({
      overflow: document.documentElement.scrollWidth > innerWidth,
      root: document.getElementById('root').getBoundingClientRect().width,
      background: getComputedStyle(document.body).backgroundColor,
      brokenImages: [...document.images].filter(image => image.complete && image.naturalWidth === 0).map(image => image.src),
    }));
    check(!layout.overflow, `No overflow at ${width}`);
    check(layout.root === width, `Full-width root at ${width}`);
    check(layout.background === 'rgb(20, 25, 22)', `Dark even with light OS preference at ${width}`);
    check(layout.brokenImages.length === 0, `Images load at ${width}`);
  }
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('button', { name: 'Open navigation' }).click();
  await page.locator('header nav').getByRole('link', { name: 'Writing', exact: true }).click();
  check(await page.getByRole('button', { name: 'Open navigation' }).getAttribute('aria-expanded') === 'false', 'Mobile menu closes after navigation');
  await page.setViewportSize({ width: 1440, height: 1000 });
  for (const name of ['Replies', 'Social', 'Terminal', 'Coding']) {
    await page.getByRole('tab', { name, exact: true }).click();
    check(await page.getByRole('tab', { name, exact: true }).getAttribute('aria-selected') === 'true', `${name} example selects`);
  }
  await page.getByRole('tab', { name: 'Coding', exact: true }).focus();
  await page.keyboard.press('ArrowRight');
  check(await page.getByRole('tab', { name: 'Replies', exact: true }).getAttribute('aria-selected') === 'true', 'Keyboard tabs');
  // Stub only the clipboard boundary: do not replace the user's system clipboard during tests.
  await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async text => { window.__testCopy = text; } } }));
  await page.getByRole('button', { name: 'Copy example', exact: true }).click();
  check(await page.evaluate(() => window.__testCopy?.startsWith('Tomorrow morning')), 'Copy receives transformed example');
  await page.getByRole('status').filter({ hasText: 'Copied' }).waitFor();
  await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => { throw new Error('denied'); } } }));
  await page.getByRole('button', { name: 'Copy example', exact: true }).click();
  await page.getByText('Select the example text and copy it manually.').waitFor();
  for (const [name, asset] of [['Give it your context', 'writing-profile-dark'], ['Adapt to the destination', 'writing-platforms-dark'], ['Set your style', 'writing-dark']]) {
    await page.getByRole('button', { name: new RegExp(name) }).click();
    check((await page.locator('#writing-preview img').getAttribute('src')).includes(asset), `${name} preview`);
  }
  await page.locator('summary').filter({ hasText: 'What is stored' }).click();
  check(await page.locator('details[open]').count() === 1, 'FAQ opens');
  check((await page.request.get('http://127.0.0.1:4175/setup.md')).status() === 200, 'Setup download exists');
  check(await page.evaluate(() => !/[—–]/.test(document.body.innerText)), 'No decorative long dashes');
  await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'no-preference' });
  await page.goto('http://127.0.0.1:4175');
  const states = new Set();
  for (let i = 0; i < 7; i++) {
    await page.waitForTimeout(1200);
    const visible = await page.locator('.status-frame').evaluateAll(images => images.filter(image => Number(getComputedStyle(image).opacity) > .6).map(image => image.className));
    visible.forEach(state => states.add(state));
  }
  check(states.size === 3, `All three statuses animate (saw ${states.size})`);
  await page.locator('footer').scrollIntoViewIfNeeded();
  await page.waitForTimeout(1000);
  if (failures.length) throw new Error(failures.join('\n'));
  console.log('PASS: 5 viewport widths, dark-only appearance, 3 native status states, reduced motion, keyboard tabs, mobile nav, preview switching, clipboard success/error boundary, FAQ, setup link and footer.');
}
