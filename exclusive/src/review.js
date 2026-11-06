const $ = selector => document.querySelector(selector);
const status = message => { $('#status').textContent = message; };
const uid = () => crypto.randomUUID();
let project, active, db, saveTimer;
let library = [];
let saveQueue = Promise.resolve();
const current = () => project.combinations.find(c => c.id === active);
const readData = blob => new Promise((resolve, reject) => {
  const reader = new FileReader();
  reader.onload = () => resolve(reader.result);
  reader.onerror = () => reject(new Error('Não foi possível ler o arquivo.'));
  reader.readAsDataURL(blob);
});
async function dimensions(source) {
  const img = new Image(); img.src = source; await img.decode();
  return { width: img.naturalWidth, height: img.naturalHeight };
}
function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('exclusive-image-review', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('projects');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
function storage(mode, value, key = 'workspace') {
  return new Promise((resolve, reject) => {
    const tx = db.transaction('projects', mode);
    const store = tx.objectStore('projects');
    const request = mode === 'readonly' ? store.get(key) : store.put(value, key);
    tx.oncomplete = () => resolve(request.result);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}
function persist() {
  clearTimeout(saveTimer);
  status('Alterações em memória. Salvando neste navegador…');
  saveTimer = setTimeout(() => {
    const snapshot = structuredClone({ projects: library, selected: project.id });
    saveQueue = saveQueue.then(async () => {
      if (!db) throw new Error('Armazenamento indisponível');
      await storage('readwrite', snapshot);
      status('Salvo neste navegador. Exporte o projeto para compartilhar ou guardar uma cópia.');
    }).catch(() => status('Não foi possível salvar no navegador. Exporte o projeto para não perder o trabalho.'));
  }, 350);
}
function initialProject() {
  return { format: 'exclusive-image-review', version: 1, id: uid(), name: 'Novo projeto', assets: [], combinations: [
    { id: uid(), name: 'Opção 1', environment: '', unit: '', typology: '', view: 'perspective', notes: '', layers: [] }
  ] };
}
function renderProjects() {
  $('#projects').replaceChildren(...library.map(p => {
    const option = new Option(p.name || 'Sem nome', p.id); option.selected = p.id === project.id; return option;
  }));
}
function renderSelect() {
  $('#combination').replaceChildren(...project.combinations.map(c => {
    const option = new Option(c.name || 'Sem nome', c.id); option.selected = c.id === active; return option;
  }));
}
function renderPreview() {
  const c = current();
  const visible = c.layers.filter(l => l.visible).map(l => project.assets.find(a => a.id === l.assetId));
  $('#preview-title').textContent = c.name || 'Sem nome';
  $('#scene').replaceChildren(...visible.map(a => { const img = new Image(); img.src = a.data; img.alt = a.name; return img; }));
  const base = visible[0];
  $('#scene').style.aspectRatio = base ? `${base.width}/${base.height}` : '16/9';
  $('#dimensions').textContent = base ? `${visible.length} camada(s) visível(is) · Quadro ${base.width} × ${base.height} px` : 'Importe imagens e marque as camadas para começar.';
  const mismatch = visible.some(a => a.width !== base.width || a.height !== base.height);
  $('#warning').textContent = [mismatch ? 'Atenção: as imagens têm dimensões diferentes. Confira o alinhamento.' : '', c.notes].filter(Boolean).join(' ');
}
function renderLayers() {
  const c = current();
  $('#layers').replaceChildren(...c.layers.map((layer, index) => {
    const asset = project.assets.find(a => a.id === layer.assetId);
    const row = document.createElement('div'); row.className = 'layer';
    const label = document.createElement('label');
    const input = document.createElement('input'); input.type = 'checkbox'; input.checked = layer.visible;
    input.onchange = () => { layer.visible = input.checked; renderPreview(); persist(); };
    label.append(input, document.createTextNode(asset.name));
    const info = document.createElement('small'); info.textContent = `${index + 1} · ${asset.width} × ${asset.height} px`;
    row.append(label, info);
    for (const [delta, text, title] of [[-1,'↑','Mover para trás'],[1,'↓','Mover para frente']]) {
      const button = document.createElement('button'); button.textContent = text; button.title = title; button.setAttribute('aria-label', `${title}: ${asset.name}`);
      button.disabled = index + delta < 0 || index + delta >= c.layers.length;
      button.onclick = () => { [c.layers[index],c.layers[index + delta]] = [c.layers[index + delta],c.layers[index]]; renderLayers(); renderPreview(); persist(); };
      row.append(button);
    }
    return row;
  }));
}
function render() {
  renderProjects();
  $('#project-name').value = project.name || '';
  renderSelect();
  for (const key of ['name','environment','unit','typology','view','notes']) $(`#${key}`).value = current()[key] || '';
  $('#delete').disabled = project.combinations.length === 1;
  renderLayers(); renderPreview();
}
async function validate(value) {
  if (value?.format !== 'exclusive-image-review' || value.version !== 1 || !Array.isArray(value.assets) || !Array.isArray(value.combinations) || !value.combinations.length) throw new Error('Formato de projeto inválido.');
  const ids = new Set();
  const assets = [];
  for (const a of value.assets) {
    if (typeof a.id !== 'string' || ids.has(a.id) || typeof a.name !== 'string' || typeof a.data !== 'string' || !/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(a.data)) throw new Error('Imagem inválida no projeto.');
    ids.add(a.id); assets.push({ id: a.id, name: a.name, data: a.data, ...await dimensions(a.data) });
  }
  const comboIds = new Set();
  const combinations = value.combinations.map(c => {
    if (typeof c.id !== 'string' || comboIds.has(c.id) || !['name','environment','notes'].every(k => typeof c[k] === 'string') || !['perspective','floor-plan'].includes(c.view) || !Array.isArray(c.layers)) throw new Error('Combinação inválida.');
    comboIds.add(c.id); const seen = new Set();
    const layers = c.layers.map(l => {
      if (!ids.has(l.assetId) || seen.has(l.assetId) || typeof l.visible !== 'boolean') throw new Error('Camada inválida.');
      seen.add(l.assetId); return { assetId: l.assetId, visible: l.visible };
    });
    for (const a of assets) if (!seen.has(a.id)) layers.push({ assetId: a.id, visible: false });
    const metadata = {};
    for (const key of ['unit','typology']) {
      if (c[key] !== undefined && typeof c[key] !== 'string') throw new Error('Identificação inválida.');
      if (c[key] !== undefined) metadata[key] = c[key];
    }
    return { id: c.id, name: c.name, environment: c.environment, view: c.view, notes: c.notes, layers, ...metadata };
  });
  return { format: value.format, version: 1, assets, combinations, ...(typeof value.name === 'string' ? {name:value.name} : {}) };
}
$('#projects').onchange = event => {
  project = library.find(p => p.id === event.target.value); active = project.combinations[0].id; render(); persist();
};
$('#new-project').onclick = () => {
  project = initialProject(); library.push(project); active = project.combinations[0].id; render(); persist(); $('#project-name').focus();
};
$('#project-name').oninput = event => { project.name = event.target.value; renderProjects(); persist(); };
$('#combination').onchange = event => { active = event.target.value; render(); };
for (const key of ['name','environment','unit','typology','view','notes']) $(`#${key}`).addEventListener('input', event => {
  current()[key] = event.target.value; renderSelect(); renderPreview(); persist();
});
$('#background').onchange = event => { $('#scene').dataset.background = event.target.value; };
$('#new').onclick = () => {
  const c = { id: uid(), name: 'Nova combinação', environment: current().environment, unit: current().unit || '', typology: current().typology || '', view: 'perspective', notes: '', layers: project.assets.map(a => ({ assetId: a.id, visible: false })) };
  project.combinations.push(c); active = c.id; render(); persist(); $('#name').focus();
};
$('#duplicate').onclick = () => {
  const c = structuredClone(current()); c.id = uid(); c.name += ' — cópia';
  project.combinations.push(c); active = c.id; render(); persist();
};
$('#delete').onclick = () => {
  if (project.combinations.length <= 1 || !confirm(`Excluir a combinação “${current().name}”? As imagens serão mantidas.`)) return;
  project.combinations = project.combinations.filter(c => c.id !== active); active = project.combinations[0].id; render(); persist();
};
$('#images').onchange = async event => {
  const files = [...event.target.files]; event.target.value = ''; const errors = [];
  const targetProject = project;
  status('Importando imagens…');
  for (const file of files) {
    try {
      if (!['image/png','image/jpeg','image/webp'].includes(file.type)) throw new Error('Use PNG, JPG ou WebP');
      const data = await readData(file);
      if (targetProject.assets.some(a => a.name === file.name && a.data === data)) continue;
      const a = { id: uid(), name: file.name, data, ...await dimensions(data) };
      targetProject.assets.push(a);
      for (const c of targetProject.combinations) c.layers.push({ assetId: a.id, visible: false });
    } catch (error) { errors.push(`${file.name}: ${error.message}`); }
  }
  render(); persist();
  if (errors.length) alert(`Alguns arquivos não foram importados:\n${errors.join('\n')}`);
};
$('#export').onclick = () => {
  const blob = new Blob([JSON.stringify(project)], { type: 'application/json' });
  const url = URL.createObjectURL(blob); const link = document.createElement('a');
  link.href = url; link.download = `exclusive-combinacoes-${new Date().toISOString().slice(0,10)}.json`; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
  status('Exportação solicitada. O arquivo inclui todas as imagens, combinações e observações.');
};
$('#project-file').onchange = async event => {
  const file = event.target.files[0]; event.target.value = ''; if (!file) return;
  try {
    status('Conferindo projeto…'); const imported = await validate(JSON.parse(await file.text()));
    imported.id = uid(); imported.name ||= file.name.replace(/\.json$/i, '');
    library.push(imported); project = imported; active = project.combinations[0].id; render(); persist();
  } catch (error) { status(`Não foi possível abrir: ${error.message}`); }
};
async function start() {
  document.querySelectorAll('button,input,select,textarea').forEach(el => { el.disabled = true; });
  try {
    let cached;
    try { db = await openDB(); cached = await storage('readonly'); } catch { db = null; }
    if (cached?.projects?.length) {
      library = await Promise.all(cached.projects.map(async p => ({ ...await validate(p), id: p.id })));
      project = library.find(p => p.id === cached.selected) || library[0];
    } else {
      const previous = db ? await storage('readonly', undefined, 'current') : null;
      if (previous) library.push({ ...await validate(previous), id: uid(), name: 'Revisão anterior — área social' });
      project = initialProject(); library.push(project);
    }
    active = project.combinations[0].id;
    document.querySelectorAll('button,input,select,textarea').forEach(el => { el.disabled = false; });
    render(); persist();
  } catch (error) { status(`Não foi possível iniciar a revisão: ${error.message}. Recarregue a página para tentar novamente.`); }
}
start();
