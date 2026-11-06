const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../src/review.js'), 'utf8').replace(/start\(\);\s*$/, '');
const pixel = 'data:image/png;base64,iVBORw0KGgo=';
function boot(value) {
  const nodes = new Map();
  class Image { naturalWidth = 5000; naturalHeight = 1770; async decode() {} }
  const context = vm.createContext({ Image, value, crypto: require('node:crypto').webcrypto, document: { querySelector: id => {
    if (!nodes.has(id)) nodes.set(id, { addEventListener() {} });
    return nodes.get(id);
  } } });
  vm.runInContext(source, context);
  return code => vm.runInContext(code, context);
}
function fixture() {
  return { format: 'exclusive-image-review', version: 1,
    assets: ['base','wall','glass'].map(id => ({ id, name: `${id}.png`, data: pixel })),
    combinations: [
      { id:'a', name:'Padrão', environment:'Social', view:'perspective', notes:'Falta porta', layers:[{assetId:'base',visible:true},{assetId:'wall',visible:true},{assetId:'glass',visible:false}] },
      { id:'b', name:'Outra', environment:'Social', view:'floor-plan', notes:'', layers:[{assetId:'glass',visible:true},{assetId:'base',visible:true},{assetId:'wall',visible:false}] }
    ] };
}
test('portable project round trip preserves image bytes, notes, visibility and independent layer order', async () => {
  const value = fixture(); const run = boot(value);
  const result = JSON.parse(JSON.stringify(await run('validate(JSON.parse(JSON.stringify(value)))')));
  assert.deepEqual(result.combinations, value.combinations);
  assert.equal(result.assets[0].data, pixel);
  assert.equal(result.assets[0].width, 5000);
});
test('invalid image sources and dangling layer references reject the entire import', async () => {
  const remote = fixture(); remote.assets[0].data = 'https://example.com/image.png';
  await assert.rejects(boot(remote)('validate(value)'), /Imagem inválida/);
  const dangling = fixture(); dangling.combinations[0].layers[0].assetId = 'missing';
  await assert.rejects(boot(dangling)('validate(value)'), /Camada inválida/);
  const duplicate = fixture(); duplicate.assets[1].id = duplicate.assets[0].id;
  await assert.rejects(boot(duplicate)('validate(value)'), /Imagem inválida/);
});
test('new projects start empty and have independent libraries and combination identifiers', () => {
  const run = boot();
  const a = run('initialProject()'); const b = run('initialProject()');
  assert.equal(a.assets.length, 0);
  assert.equal(a.combinations[0].environment, '');
  assert.equal(a.combinations[0].unit, '');
  assert.notEqual(a.id, b.id);
  assert.notEqual(a.combinations[0].id, b.combinations[0].id);
  a.assets.push({ id: 'test' });
  assert.equal(b.assets.length, 0);
});
test('unit and typology survive export and reopening', async () => {
  const value = fixture(); value.name = 'Unidade 401';
  value.combinations[0].unit = '401'; value.combinations[0].typology = '2 quartos';
  const result = await boot(value)('validate(value)');
  assert.equal(result.name, 'Unidade 401');
  assert.equal(result.combinations[0].unit, '401');
  assert.equal(result.combinations[0].typology, '2 quartos');
});
