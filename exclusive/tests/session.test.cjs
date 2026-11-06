const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8').replace(/^export /gm, '');
const units = ['1209A','1210A'].map(id => ({ id, label: id, tower: 'Teste', floor: '12', type: '3 Quartos', termination: '09A', active: true, plantDeadline: 'Sem prazo' }));
function boot(extra = {}) {
  const notices = [];
  const context = vm.createContext({
    document: { querySelector: selector => selector === '#app' ? { innerHTML: '', insertAdjacentHTML() {} } : null,
      querySelectorAll: () => [], createElement: () => ({}), body: { appendChild: e => notices.push(e.textContent) } },
    setTimeout: () => {}, clearTimeout: () => {}, options: { units, modules: [], customers: [], onSignOut() {}, ...extra }
  });
  vm.runInContext(source, context); vm.runInContext('mountConfigurator(options)', context);
  return { run: code => vm.runInContext(code, context), notices };
}
test('leaving and reopening a unit discards unsent choices', async () => {
  const p = boot(); await p.run("selectApartment('1209A')");
  p.run("state.stone='bellagio'; showApartments()"); await p.run("selectApartment('1209A')");
  assert.equal(p.run('state.stone'),'sao-marco');
  assert.equal(p.run('state.socialPlant'),'social-original');
});
test('unit switching starts from the defaults of the new unit', async () => {
  const p = boot({ defaultsForUnit: id => id === '1210A' ? { stone: 'bellagio' } : {} });
  await p.run("selectApartment('1209A')"); p.run("state.service='service-yes'");
  await p.run("selectApartment('1210A')");
  assert.equal(p.run('state.stone'),'bellagio'); assert.equal(p.run('state.service'),'service-no');
  await p.run("selectApartment('1209A')"); assert.equal(p.run('state.service'),'service-no');
});
test('old saved drafts are ignored and no save or proposal action is rendered', async () => {
  const p = boot({ savedDrafts: [{unit_id:'1209A',selections:{stone:'bellagio'}}] });
  await p.run("selectApartment('1209A')");
  assert.equal(p.run('state.stone'),'sao-marco');
  assert.doesNotMatch(p.run('headerHtml() + reviewHtml()'),/Salvar progresso|Enviar proposta|parecer|envio 1 de 4/i);
  assert.match(p.run('sessionWorkflowHtml()'),/descartadas ao sair/);
});
test('an access response arriving after logout cannot reopen the unit', async () => {
  let finish; const p = boot({ onOpen: () => new Promise(resolve => {finish=resolve;}) });
  const pending = p.run("selectApartment('1209A')"); p.run('clearConfigurator()'); finish(); await pending;
  assert.equal(p.run('state.apartmentId'),null); assert.equal(p.run('DATA.apartments.length'),0);
});
test('the latest unit opening wins over an older response', async () => {
  const finish = {}; const p = boot({ onOpen: id => new Promise(resolve => {finish[id]=resolve;}) });
  const a=p.run("selectApartment('1209A')"), b=p.run("selectApartment('1210A')");
  finish['1210A'](); await b; finish['1209A'](); await a;
  assert.equal(p.run('state.apartmentId'),'1210A');
});
test('denied access keeps the unit closed and reports the failure', async () => {
  const p=boot({onOpen:async()=>{throw Error('Acesso revogado');}}); await p.run("selectApartment('1209A')");
  assert.equal(p.run('state.apartmentId'),null); assert.equal(p.notices.at(-1),'Acesso revogado');
});

test('inactive cards open a status notice without opening a configurator session', async () => {
  let opens=0;
  const p=boot({units:[{...units[0],active:false,customizationStatus:'pending'}],onOpen:async()=>{opens++;}});
  await p.run("selectApartment('1209A')");
  assert.equal(opens,0);assert.equal(p.run('state.apartmentId'),null);
  assert.match(p.run('unitModalHtml()'),/apartment-card--unavailable/);
  assert.match(p.run('unavailableUnitHtml()'),/temporariamente indisponível/);
  p.run("DATA.apartments[0].customizationStatus='completed'");
  assert.match(p.run('unavailableUnitHtml()'),/Personalização concluída/);
});
