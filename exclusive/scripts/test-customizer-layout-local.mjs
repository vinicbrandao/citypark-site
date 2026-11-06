import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

// Layout and UI state only: no authentication or database writes.
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CITYPARK_PLAYWRIGHT_PATH || 'playwright');
const url = process.env.CITYPARK_UI_URL || 'http://127.0.0.1:5173/exclusive/';
assert.ok(['127.0.0.1', 'localhost'].includes(new URL(url).hostname), 'Local UI only');
mkdirSync('outputs/qa', { recursive: true });
const browser = await chromium.launch({ channel: process.env.CITYPARK_BROWSER_CHANNEL || 'msedge', headless: true });
const errors = [];

async function previewFits(page) {
  await page.locator('.preview-zone img').evaluateAll(images => Promise.all(images.map(image => image.decode())));
  const result = await page.locator('.preview-zone').evaluate(zone => {
    const frame = zone.querySelector('.social-perspective, .material-preview');
    const rect = frame.getBoundingClientRect();
    const parent = zone.getBoundingClientRect();
    const images = [...frame.querySelectorAll('img')];
    return {
      height: parent.height,
      inside: rect.left >= parent.left - 1 && rect.top >= parent.top - 1 && rect.right <= parent.right + 1 && rect.bottom <= parent.bottom + 1,
      noScroll: zone.scrollHeight <= zone.clientHeight && zone.scrollWidth <= zone.clientWidth,
      fitted: images.length > 0 && images.every(image => {
        const box = image.getBoundingClientRect();
        return image.naturalWidth > 0 && getComputedStyle(image).objectFit === 'contain' &&
          Math.abs(box.width - rect.width) < 1 && Math.abs(box.height - rect.height) < 1;
      })
    };
  });
  if (await page.locator('.material-preview').count()) {
    const ratio = await page.locator('.material-preview').evaluate(frame => frame.getBoundingClientRect().width / frame.getBoundingClientRect().height);
    assert.ok(Math.abs(ratio - 4000 / 1894) < 0.025, `Kitchen frame must match the complete image: ${ratio}`);
    assert.equal(await page.locator('.material-cards .card-copy').evaluateAll(copies => copies.every(copy => copy.scrollHeight <= copy.clientHeight)), true, 'Material card text is clipped');
    const thumbnails = await page.locator('.material-thumbnail').evaluateAll(async elements => {
      const cache = window.thumbnailAssetChecks ||= {};
      return Promise.all(elements.map(async element => {
        const imageElement = element.querySelector('image');
        const source = imageElement.getAttribute('href');
        if (!cache[source]) {
          const image = new Image(); image.src = source; await image.decode();
          const canvas = document.createElement('canvas'); canvas.width = image.naturalWidth; canvas.height = image.naturalHeight;
          const context = canvas.getContext('2d', { willReadFrequently:true }); context.drawImage(image,0,0);
          const pixels = context.getImageData(0,0,canvas.width,canvas.height).data;
          let left=canvas.width,top=canvas.height,right=-1,bottom=-1;
          for(let y=0;y<canvas.height;y++) for(let x=0;x<canvas.width;x++) if(pixels[(y*canvas.width+x)*4+3]) {
            left=Math.min(left,x);top=Math.min(top,y);right=Math.max(right,x);bottom=Math.max(bottom,y);
          }
          cache[source] = {left,top,right,bottom};
        }
        const content=cache[source],frame=element.viewBox.baseVal,box=element.getBoundingClientRect();
        return box.width>0 && box.height>=36 && content.right>=content.left &&
          frame.x<=content.left && frame.y<=content.top && frame.x+frame.width>content.right && frame.y+frame.height>content.bottom;
      }));
    });
    assert.equal(thumbnails.length, 2);
    assert.ok(thumbnails.every(Boolean), 'Thumbnail hides part of its item');
  }
  else {
    const ratio = await page.locator('.social-perspective').evaluate(frame => frame.clientWidth / frame.clientHeight);
    assert.ok(Math.abs(ratio - 5000 / 1770) < 0.025, `Image frame must match its image ratio: ${ratio}`);
    const cards = await page.locator('.plant-cards').evaluate(container => ({
      noVerticalScroll: container.scrollHeight <= container.clientHeight,
      complete: [...container.querySelectorAll('.catalog-card')].every(card => {
        const copy = card.querySelector('.card-copy');
        return card.getBoundingClientRect().height === Number.parseFloat(getComputedStyle(card).getPropertyValue('--plant-card-height')) && copy.scrollHeight <= copy.clientHeight;
      })
    }));
    assert.ok(cards.noVerticalScroll && cards.complete, JSON.stringify(cards));
  }
  assert.ok(result.inside && result.noScroll && result.fitted, JSON.stringify(result));
  assert.equal(await page.locator('.config-shell').evaluate(shell => shell.scrollWidth <= shell.clientWidth), true,
    'Main layout has horizontal overflow');
  const staticLayout = await page.evaluate(() => {
    const selectors = ['html', 'body', '#app', '.configurator-screen', '.config-shell', '.center-workspace'];
    const overflow = selectors.filter(selector => {
      const element = document.querySelector(selector);
      return element.scrollHeight > element.clientHeight + 1;
    });
    const bounds = document.querySelector('.center-workspace').getBoundingClientRect();
    const viewport = window.innerHeight;
    const clippedControls = [...document.querySelectorAll('.catalog-card .card-price,.left-nav button,.header-actions button')].filter(element => {
      if (!element.getClientRects().length) return false;
      const rect = element.getBoundingClientRect();
      return rect.top < 0 || rect.bottom > viewport + 1;
    }).map(element => element.textContent);
    return { overflow, clippedControls, bottom: bounds.bottom, viewport, imageHeight: document.querySelector('.social-perspective,.material-preview').getBoundingClientRect().height };
  });
  assert.deepEqual(staticLayout.overflow, [], JSON.stringify(staticLayout));
  assert.deepEqual(staticLayout.clippedControls, [], JSON.stringify(staticLayout));
  assert.ok(staticLayout.bottom <= staticLayout.viewport + 1 && staticLayout.imageHeight > 20, JSON.stringify(staticLayout));
}

async function mount(page, staffRole = null) {
  await page.evaluate(async staffRole => {
    const { mountConfigurator } = await import('/exclusive/app.js');
    window.layoutSaves = [];
    mountConfigurator({
      units: ['1209A', '1305B'].map(id => ({ id, label: id, tower: 'Torre Liberty', floor: '12º andar', type: '3 Quartos', termination: '09A', plantDeadline: 'A definir' })),
      modules: [], customers: [], staffRole,
      onSave: async (id, selections) => { window.layoutSaves.push({ id, selections }); return new Date().toISOString(); }
    });
  }, staffRole);
  await page.locator('[data-unit="1209A"]').click();
  assert.equal(await page.locator('.sidebar-toggle').getAttribute('aria-expanded'), 'true');
}

try {
  const page = await browser.newPage({ viewport: { width: 1366, height: 650 } });
  page.on('pageerror', error => errors.push(error.message));
  // Isolate the UI from the Auth bootstrap; use the actual configurator and CSS.
  await page.route('**/src/main.js*', route => route.fulfill({ contentType: 'application/javascript', body: 'import "../styles.css";' }));
  await page.goto(url, { waitUntil: 'networkidle' });
  await mount(page);
  await page.locator('[data-value="social-standard"]').click();
  assert.equal(await page.locator('.environment-preview-heading, .environment-preview-note').count(), 0);
  assert.equal((await page.locator('.environment-preview').innerText()).trim(), '');
  assert.equal(await page.locator('[data-action="go-materials"], .catalog-foot').count(), 0);
  assert.doesNotMatch(await page.locator('.plant-workspace').innerText(), /ETAPA 2|ALTERAÇÕES DA PLANTA|Configuração de planta completa/i);
  await previewFits(page);
  const stage = await page.locator('.preview-zone').boundingBox();
  await page.mouse.move(stage.x + stage.width / 2, stage.y + stage.height / 2);
  await page.mouse.wheel(0, 700);
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal((await page.locator('.preview-zone').boundingBox()).y, stage.y);
  assert.equal(await page.locator('.center-workspace').evaluate(element => element.scrollTop), 0);
  assert.equal(await page.locator('.social-perspective img').count(), 3);
  const cardSizes = () => page.locator('.plant-cards .catalog-card').evaluateAll(cards => cards.map(card => ({ width: card.getBoundingClientRect().width, height: card.getBoundingClientRect().height })));
  const standardSizes = await cardSizes();
  assert.deepEqual(standardSizes.slice(0, 2), [{ width: 220, height: 140 }, { width: 220, height: 140 }]);
  // Stress one description without changing the catalog or backend data.
  const longDescription = await page.addStyleTag({ content: `[data-value="social-full"] .card-copy p::after { content: "${' Descrição adicional bastante longa para conferir a largura independente do card.'.repeat(12)}"; }` });
  await page.locator('.sidebar-toggle').click();
  const longSizes = await cardSizes();
  assert.deepEqual(longSizes.slice(0, 3), standardSizes.slice(0, 3), 'One long description changed another card');
  assert.ok(longSizes[3].width > standardSizes[3].width);
  assert.ok(longSizes.every(card => card.height === 140));
  await previewFits(page);
  await longDescription.evaluate(style => style.remove());
  await page.locator('.sidebar-toggle').click();
  assert.deepEqual(await cardSizes(), standardSizes);
  console.log('OK: fixed 220x140 base; a longer description expands only its own card horizontally');
  await page.screenshot({ path: resolve('outputs/qa/customizer-expanded.png') });
  const expanded = await page.locator('.center-workspace').boundingBox();
  const expandedImage = await page.locator('.social-perspective').boundingBox();
  await page.getByRole('button', { name: 'Recolher menu lateral', exact: true }).click();
  assert.equal(await page.locator('.sidebar-toggle').getAttribute('aria-expanded'), 'false');
  assert.equal(await page.locator('.sidebar-toggle').evaluate(button => document.activeElement === button), true);
  assert.equal(await page.locator('[data-nav="plant"] b').isVisible(), false);
  const collapsed = await page.locator('.center-workspace').boundingBox();
  assert.ok(collapsed.width - expanded.width >= 100);
  const collapsedImage = await page.locator('.social-perspective').boundingBox();
  assert.ok(collapsedImage.width - expandedImage.width >= 100, 'The image itself must expand with the workspace');
  assert.ok(Math.abs(collapsedImage.width - collapsed.width) <= 2, 'Collapsed preview should occupy the available width at the reference viewport');
  await previewFits(page);
  await page.screenshot({ path: resolve('outputs/qa/customizer-collapsed.png') });

  await page.getByRole('button', { name: 'BANCADAS', exact: true }).click();
  const collapsedKitchen = await page.locator('.material-preview').boundingBox();
  await page.locator('.sidebar-toggle').click();
  const expandedKitchen = await page.locator('.material-preview').boundingBox();
  assert.ok(collapsedKitchen.width > expandedKitchen.width + 30, 'Kitchen must also grow with the collapsed sidebar');
  await page.locator('.sidebar-toggle').click();
  assert.equal(await page.locator('.sidebar-toggle').getAttribute('aria-expanded'), 'false');
  await page.locator('[data-material-group="stone"]').click();
  await page.locator('[data-value="bellagio"]').click();
  await previewFits(page);
  assert.equal(await page.locator('[data-action="save"]').count(), 0);
  assert.equal(await page.locator('[data-value="bellagio"].selected').count(), 1);
  await page.screenshot({ path: resolve('outputs/qa/customizer-materials.png') });
  await page.getByRole('button', { name: 'Expandir menu lateral', exact: true }).press('Enter');
  assert.equal(await page.locator('.sidebar-toggle').getAttribute('aria-expanded'), 'true');
  assert.equal(await page.locator('[data-value="bellagio"]').evaluate(button => button.classList.contains('selected')), true);
  for (const group of ['counter','stone','rodamao','service']) {
    await page.locator(`[data-material-group="${group}"]`).click();
    await page.locator('[data-material-choice]').last().click();
    await previewFits(page);
    await page.locator('.materials-catalog').screenshot({ path:resolve(`outputs/qa/countertops-${group}.png`) });
  }
  await page.getByRole('button', { name: 'PLANTA', exact: true }).click();
  assert.equal(await page.locator('[data-value="social-standard"]').evaluate(button => button.classList.contains('selected')), true);
  await page.locator('[data-plant-group="suite"]').click();
  await page.getByRole('button', { name: 'Recolher menu lateral', exact: true }).click();
  assert.equal(await page.locator('.environment-preview-empty').isVisible(), true);
  await page.locator('[data-plant-group="social"]').click();
  await page.getByRole('button', { name: 'PISO', exact: true }).click();
  assert.equal(await page.locator('.plant-workspace').count(), 1, 'Unavailable module must not navigate');
  await page.locator('[data-action="help"]').click();
  assert.equal(await page.locator('.exclusive-help-modal').isVisible(), true);
  await page.locator('[data-action="close-help"]').last().click();
  await page.locator('[data-action="review"]').click();
  assert.equal(await page.locator('.review-modal').isVisible(), true);
  await page.locator('[data-action="close-review"]').last().click();
  await page.locator('[data-action="change-unit"]').click();
  await page.locator('[data-unit="1305B"]').click();
  assert.equal(await page.locator('.sidebar-toggle').getAttribute('aria-expanded'), 'true', 'New unit must open expanded');
  await page.locator('[data-value="social-original"]').click();
  await page.locator('[data-plant-group="suite"]').click();
  await page.locator('[data-value="suite-standard"]').click();
  await page.locator('[data-plant-group="social"]').click();
  console.log('OK: collapsed navigation, focus/keyboard, session selections, review and unit reset');

  // Effective CSS viewports corresponding to browser zoom on a 1366 x 650 display.
  for (const [width, height, label] of [[1437, 678, 'wireframe'], [1920, 1080, 'large'], [1366, 650, '100'], [1093, 520, '125'], [911, 433, '150'], [683, 325, '200'], [390, 844, 'mobile']]) {
    await page.setViewportSize({ width, height });
    for (const collapsedState of [false, true]) {
      if ((await page.locator('.sidebar-toggle').getAttribute('aria-expanded') === 'false') !== collapsedState) await page.locator('.sidebar-toggle').click();
      await previewFits(page);
      await page.getByRole('button', { name: 'BANCADAS', exact: true }).click();
      for (const group of ['counter','stone','rodamao','service']) {
        await page.locator(`[data-material-group="${group}"]`).click();
        await previewFits(page);
      }
      await page.getByRole('button', { name: 'PLANTA', exact: true }).click();
    }
    if (label === 'mobile' || label === '125') {
      await page.locator('.sidebar-toggle').click();
      await page.evaluate(() => document.querySelector('#app').scrollTo(0, 0));
      await page.screenshot({ path: resolve(`outputs/qa/customizer-${label}.png`) });
    }
    if (width <= 850) {
      await page.getByRole('button', { name: 'Resumo', exact: true }).click();
      assert.equal(await page.locator('.review-modal').isVisible(), true);
      await page.locator('[data-action="close-review"]').last().click();
    }
    console.log(`OK: ${width}x${height} (${label}), complete layered previews with both sidebar states`);
  }
  await page.setViewportSize({ width: 1366, height: 650 });
  for (const role of ['architect', 'admin']) {
    await mount(page, role);
    await page.getByRole('button', { name: 'Recolher menu lateral', exact: true }).click();
    await page.getByRole('button', { name: 'BANCADAS', exact: true }).click();
    await previewFits(page);
    await page.locator('[data-action="review"]').click();
    assert.equal(await page.locator('[data-action="submit-proposal"]').count(), 0);
    await page.locator('[data-action="close-review"]').last().click();
    console.log(`OK: shared layout for ${role}, retaining staff actions`);
  }
  assert.deepEqual(errors, []);
} finally {
  await browser.close();
}
