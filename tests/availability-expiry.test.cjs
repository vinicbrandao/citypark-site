const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

test('resumo público usa apenas dados confirmados e falha fechado', () => {
  let update, fail, stopped = 0;
  const refs = [];
  const context = vm.createContext({
    db: {},
    doc: () => 'summary',
    console: { error() {} },
    onSnapshot(ref, options, callback, error) {
      refs.push(ref);
      update = callback;
      fail = error;
      return () => stopped++;
    }
  });
  vm.runInContext(fs.readFileSync('js/disponibilidade.js', 'utf8')
    .replace(/^import .*;\r?\n/gm, '').replace(/export /g, ''), context);
  let result;
  const stop = context.watchAvailability(value => { result = JSON.parse(JSON.stringify(value)); });
  assert.deepEqual(refs, ['summary']);

  const snapshot = (data, fromCache = false) => ({
    exists: () => Boolean(data),
    metadata: { fromCache },
    data: () => data
  });
  const summary = { schemaVersao: 2, unidades: {
    '1401 A': { unidade: '1401 A', status: 'disponivel' },
    '1402A': { status: 'vendida' }
  } };
  update(snapshot(summary));
  assert.deepEqual(result, { '1401A': 'disponivel', '1402A': 'vendida' });
  update(snapshot(summary, true));
  assert.deepEqual(result, {});
  update(snapshot({ ...summary, schemaVersao: 1 }));
  assert.deepEqual(result, {});
  update(snapshot(null));
  assert.deepEqual(result, {});
  fail(new Error('offline'));
  assert.deepEqual(result, {});
  stop();
  assert.equal(stopped, 1);
});
