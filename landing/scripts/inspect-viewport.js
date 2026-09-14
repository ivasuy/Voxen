async (page) => {
  const before = await page.evaluate(() => ({ innerWidth, outerWidth, devicePixelRatio, clientWidth: document.documentElement.clientWidth, visualWidth: visualViewport.width, body: document.body.getBoundingClientRect().toJSON(), root: document.getElementById('root').getBoundingClientRect().toJSON(), background: getComputedStyle(document.documentElement).backgroundColor }));
  // Clear the fixed Playwright device emulation for the user's full-screen preview.
  const session = await page.context().newCDPSession(page);
  const browserWindow = await session.send('Browser.getWindowForTarget');
  await session.send('Emulation.clearDeviceMetricsOverride');
  await session.detach();
  await page.reload();
  const after = await page.evaluate(() => ({ innerWidth, outerWidth, clientWidth: document.documentElement.clientWidth, root: document.getElementById('root').getBoundingClientRect().width }));
  return { before, browserWindow, after };
}
