const DATA = {
  apartments: [],
  plant: {
    social: [
      { id: 'social-original', title: 'Padrão', subtitle: 'Mantém a planta original, sem fechamento Euroglass.', price: 0, tags: ['Padrão'] },
      { id: 'social-standard', title: 'Padrão + Euroglass', subtitle: 'Mantém a configuração principal com fechamento Euroglass.', price: 0, tags: ['Euroglass'] },
      { id: 'social-veranda', title: 'Sala e varanda integradas + Euroglass', subtitle: 'Integra sala e varanda, remove a porta da cozinha para a varanda e fecha esse vão com alvenaria.', price: 18800, tags: ['Euroglass', 'Integração'] },
      { id: 'social-full', title: 'Sala, varanda e cozinha integradas com ilha + Euroglass', subtitle: 'Integra os três ambientes, remove a bancada da varanda e adiciona ilha. A ilha ainda não está representada na perspectiva recebida.', price: 26750, tags: ['Euroglass', 'Ilha'] }
    ],
    suite: [
      { id: 'suite-standard', title: 'Suíte padrão', subtitle: 'Mantém a configuração original da suíte Master.', price: 0, tags: ['Padrão'] },
      { id: 'suite-closet', title: 'Suíte Master ampliada + closet', subtitle: 'Amplia a suíte e cria área de closet.', price: 22400, tags: ['Drywall'] },
      { id: 'suite-office', title: 'Suíte Master ampliada + gabinete/quarto', subtitle: 'Reconfigura a área da suíte para criar ambiente adicional.', price: 24800, tags: ['Drywall'] }
    ]
  },
  materials: {
    // QUANTIDADES FICTÍCIAS PARA TESTE. Substituir pelos quantitativos do Revit.
    // A bancada e o rodamão são calculados como áreas de granito em m².
    counter: [
      { id: 'counter-standard', title: 'Bancada padrão', subtitle: 'Comprimento previsto no apartamento.', topArea: 1.20, rodamaoLength: 2.40, thumb: 'assets/cozinha/bancada-padrao-sao-marco.png' },
      { id: 'counter-extended', title: 'Bancada estendida', subtitle: 'Amplia a bancada e o comprimento do rodamão acompanha automaticamente.', topArea: 1.90, rodamaoLength: 3.80, thumb: 'assets/cozinha/bancada-estendida-sao-marco.png' }
    ],
    stone: [
      { id: 'sao-marco', title: 'São Marco', subtitle: 'Granito padrão do apartamento.', unitPrice: 900, thumb: 'assets/cozinha/bancada-padrao-sao-marco.png', badge: 'Padrão' },
      { id: 'bellagio', title: 'Bellagio', subtitle: 'Opção de upgrade da bancada.', unitPrice: 1450, thumb: 'assets/cozinha/bancada-padrao-bellagio.png', badge: 'Upgrade' }
    ],
    rodamao: [
      { id: 'padrao', title: 'Altura padrão', subtitle: 'Mantém a altura prevista no memorial.', height: 0.10, thumb: 'assets/cozinha/bancada-padrao-sao-marco.png' },
      { id: '60', title: 'Rodamão 60 cm', subtitle: 'Aumenta a altura do rodamão mantendo o comprimento da bancada.', height: 0.60, thumb: 'assets/cozinha/bancada-padrao-sao-marco-rodamao-60.png' }
    ],
    service: [
      { id: 'service-no', title: 'Configuração padrão', subtitle: 'Sem bancada adicional de serviço; mantém o tanque padrão.', topArea: 0, rodamaoLength: 0, thumb: 'assets/cozinha/tanque-inox-padrao.png' },
      { id: 'service-yes', title: 'Adicionar bancada de serviço', subtitle: 'Adiciona a bancada da área de serviço.', topArea: 0.55, rodamaoLength: 1.10, thumb: 'assets/cozinha/bancada-servico-sao-marco.png' }
    ]
  }
};

const PREVIEW_APARTMENT = {
  id: 'demo-customizer', label: 'Apartamento de demonstração',
  floor: 'Dados de teste', plantDeadline: 'Sem prazo'
};

const DEFAULT_STATE = {
  apartmentId: null,
  sidebarCollapsed: false,
  module: 'plant',
  plantGroup: 'social',
  materialGroup: 'counter',
  environment: 'cozinha',
  socialPlant: 'social-original',
  suitePlant: 'suite-standard',
  counter: 'counter-standard',
  stone: 'sao-marco',
  rodamao: 'padrao',
  service: 'service-no',
  accordions: { plant: true, floor: false, counters: true, fixtures: false, metals: false, extras: false }
};

const state = { ...DEFAULT_STATE, accordions: { ...DEFAULT_STATE.accordions } };
const app = document.querySelector('#app');
let openingVersion = 0;
let backend = null;
let mountVersion = 0;
let deadlineRefresh = null;
let layoutObserver = null;

export function clearConfigurator() {
  layoutObserver?.disconnect();
  layoutObserver = null;
  if (deadlineRefresh != null) clearTimeout(deadlineRefresh);
  deadlineRefresh = null;
  ++mountVersion;
  backend = null;
  DATA.apartments = [];
  ++openingVersion;
  reviewOpen = false;
  helpOpen = false;
  managementUnitId = null;
  historyRows = null;
  customerFormOpen = false;
  customerEditingId = null;
  adminPanel = null;
  unavailableUnitId = null;
  workflowBusy = false;
  Object.assign(state, DEFAULT_STATE, { accordions: { ...DEFAULT_STATE.accordions } });
  app.innerHTML = '';
}

export function mountConfigurator(options) {
  clearConfigurator();
  backend = options;
  DATA.apartments = options.units;
  render();
}

function normalizeSelections(value = {}) {
  value ||= {};
  const catalogs = { socialPlant: DATA.plant.social, suitePlant: DATA.plant.suite,
    counter: DATA.materials.counter, stone: DATA.materials.stone,
    rodamao: DATA.materials.rodamao, service: DATA.materials.service };
  return Object.fromEntries(Object.entries(catalogs).map(([key, options]) =>
    [key, options.some(option => option.id === value[key]) ? value[key] : DEFAULT_STATE[key]]));
}

async function selectApartment(apartmentId) {
  const apartment = DATA.apartments.find(apt => apt.id === apartmentId);
  if (!apartment) return;
  if (!backend?.staffRole && apartment.active === false) {
    openUnavailableUnit(apartmentId); return;
  }
  const request = ++openingVersion;
  const version = mountVersion;
  const defaults = backend?.defaultsForUnit?.(apartmentId);
  if (defaults && Object.values(defaults).some(value => !value)) {
    showToast('O catálogo e as opções padrão desta unidade ainda estão em preparação.'); return;
  }
  try {
    await backend?.onOpen?.(apartmentId);
    if (request !== openingVersion || version !== mountVersion) return;
    openConfigurator(apartmentId, defaults);
  } catch (error) { if (version === mountVersion) showToast(error.message || 'Não foi possível abrir a unidade.'); }
}

function openConfigurator(apartmentId, defaults) {
  Object.assign(state, DEFAULT_STATE, normalizeSelections(defaults), {
    apartmentId, accordions: { ...DEFAULT_STATE.accordions }
  });
  reviewOpen = false; helpOpen = false; render();
}

function canPreview() {
  return backend?.allowPreview === true && ['admin', 'architect'].includes(backend.staffRole);
}

function isPreview() {
  return canPreview() && state.apartmentId === PREVIEW_APARTMENT.id;
}

function showApartments() {
  ++openingVersion;
  Object.assign(state, DEFAULT_STATE, { accordions: { ...DEFAULT_STATE.accordions } });
  reviewOpen = false; helpOpen = false; render();
}

function currentApartment() {
  if (isPreview()) return PREVIEW_APARTMENT;
  return DATA.apartments.find(a => a.id === state.apartmentId) || DATA.apartments[0];
}
function unitDeadlineClosed(apt = currentApartment()) {
  return Boolean(apt?.customizationClosesAt && Date.now() >= Date.parse(apt.customizationClosesAt));
}
function scheduleDeadlineRefresh() {
  if (deadlineRefresh != null) clearTimeout(deadlineRefresh);
  deadlineRefresh = null;
  const units = state.apartmentId ? [currentApartment()] : DATA.apartments;
  const remaining = units.flatMap(apt => [apt?.customizationClosesAt, ...(apt?.moduleWindows || []).flatMap(w => [w.opens_at, w.closes_at])]).map(date => Date.parse(date) - Date.now())
    .filter(delay => Number.isFinite(delay) && delay > 0);
  if (remaining.length) deadlineRefresh = setTimeout(() => {
    deadlineRefresh = null;
    if (backend) render();
  }, Math.min(Math.min(...remaining) + 20, 2147483647));
}
function find(list, id) { return list.find(x => x.id === id); }
function brl(v) { return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v || 0); }
function num(v, digits = 2) { return new Intl.NumberFormat('pt-BR', { minimumFractionDigits: digits, maximumFractionDigits: digits }).format(v || 0); }
function choicePrice(list, id) { return find(list, id)?.price || 0; }

function granitePricing() {
  const counter = find(DATA.materials.counter, state.counter) || DATA.materials.counter[0];
  const service = find(DATA.materials.service, state.service) || DATA.materials.service[0];
  const rodamao = find(DATA.materials.rodamao, state.rodamao) || DATA.materials.rodamao[0];
  const stone = find(DATA.materials.stone, state.stone) || DATA.materials.stone[0];

  const baseCounter = DATA.materials.counter[0];
  const baseService = DATA.materials.service[0];
  const baseRodamao = DATA.materials.rodamao[0];
  const baseStone = DATA.materials.stone[0];

  const countertopArea = counter.topArea + service.topArea;
  const rodamaoLength = counter.rodamaoLength + service.rodamaoLength;
  const rodamaoArea = rodamaoLength * rodamao.height;
  const totalArea = countertopArea + rodamaoArea;

  const baseCountertopArea = baseCounter.topArea + baseService.topArea;
  const baseRodamaoArea = (baseCounter.rodamaoLength + baseService.rodamaoLength) * baseRodamao.height;
  const baseTotalArea = baseCountertopArea + baseRodamaoArea;

  const selectedCost = totalArea * stone.unitPrice;
  const baseCost = baseTotalArea * baseStone.unitPrice;
  const additionalCost = Math.max(0, selectedCost - baseCost);

  return {
    countertopArea,
    rodamaoLength,
    rodamaoArea,
    totalArea,
    unitPrice: stone.unitPrice,
    baseTotalArea,
    baseUnitPrice: baseStone.unitPrice,
    selectedCost,
    baseCost,
    additionalCost,
    extraArea: Math.max(0, totalArea - baseTotalArea)
  };
}

function totalPrice() {
  return choicePrice(DATA.plant.social, state.socialPlant)
    + choicePrice(DATA.plant.suite, state.suitePlant)
    + granitePricing().additionalCost;
}
function plantComplete() { return Boolean(state.socialPlant && state.suitePlant); }
function choiceEnabled(key, value) {
  if (isPreview() || !backend?.canEdit) return true;
  const module = ['socialPlant', 'suitePlant'].includes(key) ? 'planta' : 'bancadas';
  return backend.canEdit(state.apartmentId, module) &&
    (!backend.isOptionAvailable || backend.isOptionAvailable(state.apartmentId, key, value, state));
}
function materialLabel(list, id, fallback = '—') { return find(list, id)?.title || fallback; }
function materialCardMeta(item, key) {
  if (key === 'counter') return `${num(item.topArea)} m² de bancada · ${num(item.rodamaoLength)} m de comprimento de rodamão`;
  if (key === 'stone') return `${brl(item.unitPrice)} / m²`;
  if (key === 'rodamao') return `${num(item.height * 100, 0)} cm de altura`;
  if (key === 'service') return item.topArea ? `${num(item.topArea)} m² de bancada · ${num(item.rodamaoLength)} m de rodamão` : 'Configuração incluída no padrão';
  return '';
}



function showToast(text) {
  const old = document.querySelector('.toast'); if (old) old.remove();
  const el = document.createElement('div'); el.className = 'toast'; el.textContent = text;
  document.body.appendChild(el); setTimeout(() => el.remove(), 2200);
}

function headerHtml() {
  const apt = currentApartment();
  return `<header class="app-header${state.apartmentId ? ' configurator-header' : ''}">
    <button class="wordmark" data-action="home" aria-label="Início">
      <span class="wordmark-mark">CP</span>
      <span><b>City Park</b><small>Exclusive</small></span>
    </button>
    ${state.apartmentId ? `<div class="header-unit"><span>${apt.label}</span><small>${apt.floor} · prazo de planta: ${apt.plantDeadline}</small></div>` : '<div></div>'}
    <div class="header-actions">
      ${isPreview() ? '<span class="header-btn">Prévia · valores ilustrativos</span>' : backend?.staffRole && state.apartmentId ? `<span class="header-btn">${backend.staffRole === 'admin' ? 'Administrador' : 'Arquiteta'} · atendimento</span>` : ''}
      ${state.apartmentId ? `<button class="header-btn strong" data-action="change-unit">${isPreview() ? 'Voltar às unidades' : 'Trocar unidade'}</button>` : ''}
      ${state.apartmentId ? '<button class="header-btn compact-review" data-action="compact-review">Resumo</button>' : ''}
      <button class="header-btn" data-action="logout">${!state.apartmentId ? 'Voltar ao login' : 'Sair'}</button>
    </div>
  </header>`;
}

function leftNavHtml() {
  const items = [
    ['plant', 'PLANTA', 'planta'], ['floor', 'PISO', 'piso'], ['counters', 'BANCADAS', 'bancadas'], ['fixtures', 'LOUÇAS', 'loucas'], ['metals', 'METAIS', 'metais'], ['extras', 'EXTRAS', null]
  ];
  return `<aside class="left-nav">
    <div class="left-nav-heading">
      <div class="left-nav-title">Personalize seu<br>apartamento</div>
      <button class="sidebar-toggle" data-action="toggle-sidebar" aria-controls="customizer-navigation" aria-expanded="${!state.sidebarCollapsed}" aria-label="${state.sidebarCollapsed ? 'Expandir menu lateral' : 'Recolher menu lateral'}" title="${state.sidebarCollapsed ? 'Expandir menu lateral' : 'Recolher menu lateral'}">
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M8 4v16M${state.sidebarCollapsed ? '12 9l3 3-3 3' : '16 9l-3 3 3 3'}"/></svg>
      </button>
    </div>
    <nav id="customizer-navigation" aria-label="Módulos de personalização">${items.map(([id, label, icon]) => {
      const active = (state.module === 'plant' && id === 'plant') || (state.module === 'materials' && id === 'counters');
      const available = id === 'plant' || id === 'counters';
      const iconHtml = icon
        ? `<img class="nav-icon" src="assets/icons/sidebar/icone-${icon}-branco.png" alt="" aria-hidden="true">`
        : '<span aria-hidden="true">+</span>';
      return `<button class="nav-item ${active ? 'active' : ''} ${available ? '' : 'disabled'}" data-nav="${id}" aria-label="${label}" ${active ? 'aria-current="page"' : ''} title="${label}${available ? '' : ' · Catálogo ainda não liberado'}">${iconHtml}<b>${label}</b>${available ? '' : '<em>em breve</em>'}</button>`;
    }).join('')}</nav>
    <button class="left-help" data-action="help" aria-label="Precisa de ajuda? Fale com a equipe do Exclusive." title="Fale com a equipe do Exclusive"><span aria-hidden="true">?</span><div><b>PRECISA DE AJUDA?</b><small>Fale com a equipe do Exclusive.</small></div></button>
  </aside>`;
}

function accordionRow(title, id, content) {
  const open = state.accordions[id];
  return `<section class="summary-accordion ${open ? 'open' : ''}">
    <button class="accordion-head" data-accordion="${id}"><b>${title}</b><span>${open ? '−' : '+'}</span></button>
    ${open ? `<div class="accordion-body">${content}</div>` : ''}
  </section>`;
}

function summaryPanelHtml() {
  const apt = currentApartment();
  const pricing = granitePricing();
  const counter = find(DATA.materials.counter, state.counter);
  const stone = find(DATA.materials.stone, state.stone);
  const service = find(DATA.materials.service, state.service);

  const plantContent = `<div class="summary-line"><span>Área social</span><b>${materialLabel(DATA.plant.social, state.socialPlant)}</b></div>
    <div class="summary-line"><span>Suíte Master</span><b>${materialLabel(DATA.plant.suite, state.suitePlant)}</b></div>`;

  const counterContent = `<div class="summary-line"><span>Bancada</span><b>${materialLabel(DATA.materials.counter, state.counter)}</b><em>${num(counter.topArea)} m²</em></div>
    <div class="summary-line"><span>Granito</span><b>${materialLabel(DATA.materials.stone, state.stone)}</b><em>${brl(stone.unitPrice)}/m²</em></div>
    <div class="summary-line"><span>Rodamão</span><b>${materialLabel(DATA.materials.rodamao, state.rodamao)}</b><em>${num(pricing.rodamaoArea)} m²</em></div>
    <div class="summary-line"><span>Serviço</span><b>${materialLabel(DATA.materials.service, state.service)}</b><em>${service.topArea ? num(service.topArea) + ' m²' : 'Padrão'}</em></div>
    <div class="quantity-summary">
      <div><span>Área total de granito</span><b>${num(pricing.totalArea)} m²</b></div>
      <div><span>Referência padrão</span><b>${num(pricing.baseTotalArea)} m² × ${brl(pricing.baseUnitPrice)}/m²</b></div>
      <div class="subtotal"><span>Acréscimo bancadas</span><b>+ ${brl(pricing.additionalCost)}</b></div>
    </div>`;

  return `<aside class="right-panel">
    <div class="summary-top">
      <span class="summary-kicker">RESUMO DA PERSONALIZAÇÃO</span>
      <h3>${apt.label}</h3><p>${apt.tower} · ${apt.floor}</p>
    </div>
    <div class="summary-scroll">
      ${accordionRow('PLANTA', 'plant', plantContent)}
      ${accordionRow('PISO', 'floor', '<div class="empty-category">Nenhuma escolha disponível ainda.</div>')}
      ${accordionRow('BANCADAS', 'counters', counterContent)}
      ${accordionRow('LOUÇAS', 'fixtures', '<div class="empty-category">Catálogo em preparação.</div>')}
      ${accordionRow('METAIS', 'metals', '<div class="empty-category">Catálogo em preparação.</div>')}
      ${accordionRow('EXTRAS', 'extras', '<div class="empty-category">Catálogo em preparação.</div>')}
    </div>
    <div class="summary-total">
      <span>VALOR ADICIONAL</span>
      <strong>${brl(totalPrice())}</strong>
      <small>Quantidades e preços unitários ainda fictícios. Substituir pelos dados do Revit/orçamento.</small>
      <button data-action="review">REVISAR ESCOLHAS</button>
    </div>
  </aside>`;
}

function plantPreviewHtml() {
  if (state.plantGroup === 'suite') {
    return `<div class="plan-preview environment-preview">
      <div class="environment-preview-empty"><h3>Perspectiva da Suíte Master em preparação</h3><p>As imagens deste ambiente ainda não foram recebidas.</p></div>
    </div>`;
  }
  const selected = state.socialPlant;
  const euroglass = ['social-standard', 'social-veranda', 'social-full'].includes(selected);
  const wallLayer = !selected || ['social-original', 'social-standard'].includes(selected) ? 'opcao-02.png' : selected === 'social-full' ? 'opcao-03.png' : null;
  return `<div class="plan-preview environment-preview">
    <div class="social-perspective" role="img" aria-label="Perspectiva de referência da área social${euroglass ? ' com Euroglass' : ''}">
      <img src="assets/planta/social/base-sala.png" alt="" class="social-perspective-base">
      ${wallLayer ? `<img src="assets/planta/social/${wallLayer}" alt="" class="social-perspective-layer">` : ''}
      ${euroglass ? '<img src="assets/planta/social/euroglass.png" alt="" class="social-perspective-layer">' : ''}
    </div>
  </div>`;
}

function plantCatalogHtml() {
  const list = state.plantGroup === 'social' ? DATA.plant.social : DATA.plant.suite;
  const key = state.plantGroup === 'social' ? 'socialPlant' : 'suitePlant';
  return `<div class="catalog-shell plant-catalog">
    <div class="catalog-head">
      <div><b>${state.plantGroup === 'social' ? 'Área social' : 'Suíte Master'}</b></div>
      <div class="segmented"><button class="${state.plantGroup === 'social' ? 'active' : ''}" data-plant-group="social">Área social</button><button class="${state.plantGroup === 'suite' ? 'active' : ''}" data-plant-group="suite">Suíte Master</button></div>
    </div>
    <div class="catalog-cards plant-cards">${list.map(item => `<button class="catalog-card ${state[key] === item.id ? 'selected' : ''}" data-plant-choice="${key}" data-value="${item.id}" ${choiceEnabled(key, item.id) ? '' : 'disabled'}>
      <div class="card-check">${state[key] === item.id ? '✓' : ''}</div>
      <div class="card-copy"><b>${item.title}</b><p>${item.subtitle}</p><div class="card-tags">${item.tags.map(t => `<span>${t}</span>`).join('')}</div></div>
      <div class="card-price">${item.price ? '+' + brl(item.price) : 'Sem acréscimo'}</div>
    </button>`).join('')}</div>
  </div>`;
}

function environmentTabsHtml() {
  const tabs = [
    ['sala', 'SALA'], ['cozinha', 'COZINHA'], ['suite', 'SUÍTE MASTER'], ['quarto', 'QUARTO'], ['banheiro', 'BANHEIRO'], ['varanda', 'VARANDA'], ['servico', 'SERVIÇO']
  ];
  return `<div class="environment-tabs">${tabs.map(([id, label]) => {
    const enabled = id === 'cozinha' || id === 'servico';
    return `<button class="${state.environment === id ? 'active' : ''} ${enabled ? '' : 'disabled'}" data-environment="${id}" ${enabled ? '' : 'title="Ambiente ainda sem catálogo"'}>${label}</button>`;
  }).join('')}</div>`;
}

function kitchenLayers() {
  const layers = [];
  const main = {
    'counter-standard|sao-marco|padrao': 'assets/cozinha/bancada-padrao-sao-marco.png',
    'counter-standard|sao-marco|60': 'assets/cozinha/bancada-padrao-sao-marco-rodamao-60.png',
    'counter-standard|bellagio|padrao': 'assets/cozinha/bancada-padrao-bellagio.png',
    'counter-standard|bellagio|60': 'assets/cozinha/bancada-padrao-bellagio-rodamao-60.png',
    'counter-extended|sao-marco|padrao': 'assets/cozinha/bancada-estendida-sao-marco.png',
    'counter-extended|sao-marco|60': 'assets/cozinha/bancada-estendida-rodamao-60.png',
    'counter-extended|bellagio|padrao': 'assets/cozinha/bancada-estendida-bellagio.png',
    'counter-extended|bellagio|60': 'assets/cozinha/bancada-estendida-bellagio-rodamao-60.png'
  };
  layers.push(main[`${state.counter}|${state.stone}|${state.rodamao}`]);
  if (state.service === 'service-no') {
    layers.push('assets/cozinha/tanque-inox-padrao.png');
  } else {
    const service = {
      'sao-marco|padrao': 'assets/cozinha/bancada-servico-sao-marco.png',
      'sao-marco|60': 'assets/cozinha/bancada-servico-rodamao-60-b.png',
      'bellagio|padrao': 'assets/cozinha/bancada-servico-bellagio.png',
      'bellagio|60': 'assets/cozinha/bancada-servico-rodamao-60-a.png'
    };
    layers.push(service[`${state.stone}|${state.rodamao}`]);
  }
  return layers.filter(Boolean);
}

function materialPreviewHtml() {
  return `<div class="material-preview">
    <img class="preview-base" src="assets/cozinha/cozinha-base.jpg" alt="Prévia da cozinha">
    ${kitchenLayers().map(src => `<img class="preview-layer" src="${src}" alt="Camada selecionada">`).join('')}
    <div class="preview-tools"><button title="Visualização fixa">□</button><button title="Ampliar">＋</button></div>
    <div class="preview-status"><span>${materialLabel(DATA.materials.counter, state.counter)}</span><span>${materialLabel(DATA.materials.stone, state.stone)}</span><span>${materialLabel(DATA.materials.rodamao, state.rodamao)}</span></div>
  </div>`;
}

function materialGroupData() {
  if (state.materialGroup === 'counter') return { title: 'Comprimento da bancada', subtitle: 'A geometria muda imediatamente na prévia.', key: 'counter', list: DATA.materials.counter };
  if (state.materialGroup === 'stone') return { title: 'Granito da bancada', subtitle: 'São Marco é o padrão; Bellagio é a opção de upgrade.', key: 'stone', list: DATA.materials.stone };
  if (state.materialGroup === 'rodamao') return { title: 'Altura do rodamão', subtitle: 'O comprimento acompanha a bancada; a altura é uma variável separada.', key: 'rodamao', list: DATA.materials.rodamao };
  return { title: 'Área de serviço', subtitle: 'A configuração padrão mantém o tanque; a opção adicional inclui bancada de serviço.', key: 'service', list: DATA.materials.service };
}

// Native coordinates enclosing each complete item, including a transparent margin.
// The full original canvases remain in use for the apartment composition.
const MATERIAL_THUMBNAILS = {
  'bancada-padrao-sao-marco.png': { width:3738, height:1770, viewBox:'1548 941 1013 301' },
  'bancada-estendida-sao-marco.png': { width:3738, height:1770, viewBox:'1547 941 1980 301' },
  'bancada-padrao-bellagio.png': { width:3738, height:1770, viewBox:'1548 941 1013 301' },
  'bancada-padrao-sao-marco-rodamao-60.png': { width:2047, height:969, viewBox:'840 391 570 297' },
  'tanque-inox-padrao.png': { width:3738, height:1770, viewBox:'271 922 386 339' },
  'bancada-servico-sao-marco.png': { width:3738, height:1770, viewBox:'188 923 1689 322' }
};

function materialThumbnailHtml(item) {
  if (!item.thumb) return '<div class="card-image text-icon">↕</div>';
  const frame = MATERIAL_THUMBNAILS[item.thumb.split('/').pop()];
  return `<div class="card-image">${frame
    ? `<svg class="material-thumbnail" viewBox="${frame.viewBox}" preserveAspectRatio="xMidYMid meet" role="img" aria-label="${safe(item.title)}"><image href="${safe(item.thumb)}" width="${frame.width}" height="${frame.height}"/></svg>`
    : `<img src="${safe(item.thumb)}" alt="${safe(item.title)}">`}</div>`;
}

function materialCatalogHtml() {
  const group = materialGroupData();
  return `<div class="catalog-shell materials-catalog">
    <div class="catalog-head">
      <div><b>${group.title}</b></div>
      <div class="segmented four"><button class="${state.materialGroup === 'counter' ? 'active' : ''}" data-material-group="counter">Configuração</button><button class="${state.materialGroup === 'stone' ? 'active' : ''}" data-material-group="stone">Granito</button><button class="${state.materialGroup === 'rodamao' ? 'active' : ''}" data-material-group="rodamao">Rodamão</button><button class="${state.materialGroup === 'service' ? 'active' : ''}" data-material-group="service">Serviço</button></div>
    </div>
    <div class="catalog-cards material-cards">${group.list.map(item => `<button class="catalog-card visual-card ${state[group.key] === item.id ? 'selected' : ''}" data-material-choice="${group.key}" data-value="${item.id}" ${choiceEnabled(group.key, item.id) ? '' : 'disabled'}>
      ${materialThumbnailHtml(item)}
      <div class="card-copy"><b>${item.title}</b><p>${item.subtitle}</p>${item.badge ? `<div class="card-tags"><span>${item.badge}</span></div>` : ''}</div>
      <div class="card-price">${materialCardMeta(item, group.key)}</div>
    </button>`).join('')}</div>
  </div>`;
}

function workspaceHtml() {
  if (state.module === 'plant') {
    return `<main class="center-workspace plant-workspace">
      <div class="workspace-top"><h2>Escolha a configuração de planta</h2><div class="deadline-pill">Prazo: <b>${currentApartment().plantDeadline}</b></div></div>
      <div class="preview-zone">${plantPreviewHtml()}</div>
      <div class="catalog-zone">${plantCatalogHtml()}</div>
    </main>`;
  }
  return `<main class="center-workspace materials-workspace">
    ${environmentTabsHtml()}
    <div class="preview-zone material-zone">${materialPreviewHtml()}</div>
    <div class="catalog-zone">${materialCatalogHtml()}</div>
  </main>`;
}

function configuratorHtml() {
  return `<div class="configurator-screen">${headerHtml()}<div class="config-shell${state.sidebarCollapsed ? ' sidebar-collapsed' : ''}">${leftNavHtml()}${workspaceHtml()}${summaryPanelHtml()}</div></div>`;
}

function unitModalHtml() {
  if (backend?.staffRole) return staffUnitsHtml();
  const displayLabel = value => String(value).replace(/^(\d+)([AB])$/, '$1 $2');
  return `<div class="unit-screen unit-selection-screen">
    ${headerHtml()}
    <main class="apartment-selection" aria-labelledby="apartment-selection-title">
      <div class="apartment-selection-heading">
        ${backend?.staffRole ? `<p class="apartment-profile">${backend.staffRole === 'admin' ? 'Administrador' : 'Arquiteta'}</p>` : ''}
        <h1 id="apartment-selection-title">${backend?.staffRole ? 'Selecione a unidade para atendimento' : 'Escolha seu apartamento'}</h1>
      </div>
      <div class="apartment-grid ${DATA.apartments.length === 1 ? 'apartment-grid--single' : ''}">
        ${DATA.apartments.map(apt => {
          const label = displayLabel(apt.label);
          const tower = apt.towerCode && !String(apt.tower).endsWith(` ${apt.towerCode}`)
            ? `${apt.tower} ${apt.towerCode}` : apt.tower;
          const area = Number(apt.areaM2);
          const metadata = [tower, apt.floor, apt.type, Number.isFinite(area) && area > 0
            ? `${new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(area)} m²`
            : 'Área a confirmar'];
          const closed = unitDeadlineClosed(apt);
          const unavailable = apt.active === false;
          return `<article class="apartment-card${unavailable ? ' apartment-card--unavailable' : ''}" data-apartment-id="${safe(apt.id)}" aria-labelledby="apartment-${safe(apt.id)}" ${unavailable ? `data-unavailable-unit="${safe(apt.id)}" role="button" tabindex="0" aria-describedby="unavailable-${safe(apt.id)}" aria-haspopup="dialog"` : ''}>
            <div class="apartment-image">${apt.situation
              ? `<img src="${safe(apt.situation)}" alt="Planta de localização da unidade ${safe(label)}">`
              : '<div class="apartment-image-placeholder"><span aria-hidden="true">⌂</span><p>Planta em preparação</p></div>'}</div>
            <div class="apartment-card-body">
              <h2 id="apartment-${safe(apt.id)}">${safe(label)}</h2>
              <p class="apartment-details">${metadata.filter(Boolean).map(value => `<span>${safe(value)}</span>`).join('')}</p>
              ${unavailable
                ? `<span class="apartment-access apartment-unavailable-label" id="unavailable-${safe(apt.id)}">Unidade indisponível <span aria-hidden="true">ⓘ</span></span>`
                : `<button class="apartment-access" data-unit="${safe(apt.id)}" aria-label="Acessar unidade ${safe(label)}">Acessar unidade <span aria-hidden="true">→</span></button>`}
              <div class="apartment-deadline ${closed ? 'apartment-deadline--closed' : ''}">
                <span>${closed ? 'Prazo encerrado · somente consulta' : 'Prazo final para alterações'}</span>
                ${apt.customizationClosesAt
                  ? `<time datetime="${safe(apt.customizationClosesAt)}">${safe(apt.customizationDeadline)}</time>`
                  : '<strong>Sem prazo</strong>'}
              </div>
            </div>
          </article>`;
        }).join('')}
      </div>
    </main>
  </div>`;
}

function reviewHtml() {
  const pricing = granitePricing();
  const stone = find(DATA.materials.stone, state.stone);
  return `<div class="review-overlay"><div class="review-modal">
    <button class="close-review" data-action="close-review">×</button>
    <span class="review-kicker">RESUMO DA PERSONALIZAÇÃO</span><h2>${currentApartment().label}</h2>
    <div class="review-grid">
      <section><h3>Planta</h3><p><span>Área social</span><b>${materialLabel(DATA.plant.social, state.socialPlant)}</b></p><p><span>Suíte Master</span><b>${materialLabel(DATA.plant.suite, state.suitePlant)}</b></p></section>
      <section><h3>Bancadas</h3><p><span>Configuração</span><b>${materialLabel(DATA.materials.counter, state.counter)}</b></p><p><span>Granito</span><b>${materialLabel(DATA.materials.stone, state.stone)} · ${brl(stone.unitPrice)}/m²</b></p><p><span>Rodamão</span><b>${materialLabel(DATA.materials.rodamao, state.rodamao)}</b></p><p><span>Serviço</span><b>${materialLabel(DATA.materials.service, state.service)}</b></p><p><span>Área total de granito</span><b>${num(pricing.totalArea)} m²</b></p><p><span>Acréscimo de bancadas</span><b>${brl(pricing.additionalCost)}</b></p></section>
    </div>
    <div class="review-total"><span>Valor adicional</span><strong>${brl(totalPrice())}</strong></div>
    ${sessionWorkflowHtml()}
    <button class="review-primary" data-action="close-review">Voltar ao configurador</button>
  </div></div>`;
}

let reviewOpen = false;
let helpOpen = false;
let managementUnitId = null;
let historyRows = null;
let customerFormOpen = false;
let customerEditingId = null;
let adminPanel = null;
let unavailableUnitId = null;
let workflowBusy = false;
const safe = value => String(value ?? '').replace(/[&<>"']/g, char => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
}[char]));

function openUnavailableUnit(unitId) {
  unavailableUnitId = unitId;
  render();
  document.querySelector('[data-action="close-unavailable"]')?.focus();
}
function closeUnavailableUnit() {
  const unitId = unavailableUnitId;
  unavailableUnitId = null;
  render();
  document.querySelector(`[data-unavailable-unit="${unitId}"]`)?.focus();
}
function unavailableUnitHtml() {
  const unit = DATA.apartments.find(apt => apt.id === unavailableUnitId);
  const completed = unit.customizationStatus === 'completed';
  return `<div class="review-overlay unavailable-unit-overlay"><section class="review-modal unavailable-unit-modal" role="dialog" aria-modal="true" aria-labelledby="unavailable-unit-title" aria-describedby="unavailable-unit-description">
    <button class="close-review" data-action="close-unavailable" aria-label="Fechar aviso">×</button>
    <span class="review-kicker">UNIDADE ${safe(unit.label)}</span>
    <h2 id="unavailable-unit-title">${completed ? 'Personalização concluída' : 'Unidade indisponível'}</h2>
    <p id="unavailable-unit-description">${completed
      ? 'A personalização desta unidade foi concluída. Ela está inativa e indisponível para novas alterações.'
      : 'O acesso à personalização desta unidade está temporariamente indisponível.'}</p>
    <p>Para mais informações${completed ? ' ou para solicitar a reabertura' : ''}, entre em contato com a equipe do Exclusive.</p>
    <button class="review-primary" data-action="close-unavailable">Entendi</button>
  </section></div>`;
}

function sessionWorkflowHtml() {
  return '<section class="exclusive-workflow"><h3>Sessão de personalização</h3><p>As escolhas desta sessão serão descartadas ao sair da unidade. A geração de contratos será disponibilizada em uma próxima etapa.</p></section>';
}
function helpHtml() {
  return '<div class="review-overlay"><div class="review-modal exclusive-help-modal"><button class="close-review" data-action="close-help" aria-label="Fechar">×</button><h2>Personalização</h2><p>Escolha as opções permitidas para sua unidade e confira o resumo. Ao sair, as escolhas voltam ao padrão. Para dúvidas sobre o catálogo ou prazos, entre em contato com a equipe do Exclusive.</p></div></div>';
}
function staffUnitsHtml() {
  return `<div class="unit-screen unit-selection-screen">${headerHtml()}<main class="staff-units">
    <div class="staff-heading"><div><p class="apartment-profile">${backend.staffRole === 'admin' ? 'Administrador' : 'Arquiteta'}</p><h1>Unidades do CityPark</h1></div><div class="unit-actions">${canPreview() ? '<button data-action="open-customizer-preview">Prévia da personalização</button>' : ''}${backend.staffRole === 'admin' ? `<button data-action="new-customer">Cadastrar cliente</button>${backend.permissionsV2 ? '<button data-action="customers-panel">Clientes</button><button data-action="staff-panel">Equipe</button><button data-action="notifications-panel">Avisos</button>' : ''}` : ''}<button class="header-btn" data-action="history">Histórico geral</button></div></div>
    <p class="session-notice">As personalizações ficam apenas na sessão aberta. Sair da unidade descarta as escolhas.</p>
    <div class="unit-table-scroll"><table class="unit-table"><thead><tr><th>Unidade / planta-base</th><th>Cliente</th><th>Status</th><th>Prazo geral</th><th>Módulos</th><th>Ações</th></tr></thead><tbody>
    ${DATA.apartments.map(apt => `<tr><td><strong>${safe(apt.label)}</strong><small>${safe(apt.tower)} · ${safe(apt.floor)}</small><small>${safe(apt.basePlanName)}</small></td>
      <td>${safe(apt.customer?.name || 'Sem cliente vinculado')}<small>${safe(apt.customer?.email)}</small>${backend.permissionsV2 ? `<small>${safe(apt.customer?.phone || 'Telefone não informado')}</small>${apt.customer?.active === false ? '<small>Conta inativa</small>' : ''}` : ''}</td>
      <td><span class="unit-status ${apt.active ? 'is-active' : ''}">${apt.active ? 'Ativa' : 'Inativa'}</span><small>${apt.customizationStatus === 'completed' ? 'Concluída' : 'Pendente'}</small></td>
      <td>${safe(apt.customizationDeadline || 'Sem prazo')}</td>
      <td>${(backend.modules || []).map(m => `<small>${safe(m.name)}: ${safe(formatSessionDate(apt.moduleWindows?.find(w => w.module_code === m.code)?.closes_at))}</small>`).join('')}</td>
      <td><div class="unit-actions"><button data-unit="${safe(apt.id)}">Acessar</button><button data-action="toggle-unit" data-unit-id="${safe(apt.id)}" ${!apt.active && apt.customizationStatus === 'completed' && backend.staffRole !== 'admin' ? 'disabled' : ''}>${apt.active ? 'Inativar' : 'Ativar'}</button>
      ${backend.staffRole === 'admin' ? `<button data-action="manage-unit" data-unit-id="${safe(apt.id)}">Gerenciar</button>` : ''}<button data-action="history" data-unit-id="${safe(apt.id)}">Histórico</button></div></td></tr>`).join('')}
    </tbody></table></div></main></div>`;
}
function formatSessionDate(value) {
  return value ? new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Sao_Paulo' }).format(new Date(value)) : 'Sem prazo';
}
function localDateInput(value) {
  if (!value) return '';
  const date = new Date(value);
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0,16);
}
function managementHtml() {
  const apt = DATA.apartments.find(unit => unit.id === managementUnitId);
  return `<div class="review-overlay"><div class="review-modal"><button class="close-review" data-action="close-management" aria-label="Fechar">×</button><h2>Gerenciar ${safe(apt.label)}</h2>
    <form id="unit-management-form"><label>Cliente<select name="customer"><option value="">Sem cliente</option>${backend.customers.map(c => `<option value="${safe(c.id)}" ${c.id === apt.customerId ? 'selected' : ''}>${safe(c.name)} · ${safe(c.email)}</option>`).join('')}</select></label>
    <label>Prazo geral<input type="datetime-local" name="deadline" value="${localDateInput(apt.customizationClosesAt)}"></label>
    ${backend.modules.map(m => `<label>Prazo de ${safe(m.name)}<input type="datetime-local" data-module-deadline="${safe(m.code)}" value="${localDateInput(apt.moduleWindows?.find(w => w.module_code === m.code)?.closes_at)}"></label>`).join('')}
    <p class="session-notice">Datas no horário do dispositivo. Campo vazio remove o prazo e libera alterações sem data limite.</p><button class="review-primary" type="submit">Salvar cadastro e prazos</button></form>
    ${apt.commercialReviewRevision ? `<p class="session-notice">Revenda identificada. Confira o cliente vinculado antes de liberar a personalização.</p>
      ${apt.customerId ? '<button type="button" data-action="confirm-commercial-owner">Confirmar proprietário vinculado</button>' : ''}` : ''}
    </div></div>`;
}
function historyHtml() {
  const labels = { unit_first_opened: 'Acessou a unidade pela primeira vez', unit_opened: 'Acessou a unidade', unit_status_changed: 'Alterou o status', unit_deadline_changed: 'Alterou o prazo geral', module_deadline_changed: 'Alterou o prazo do módulo', unit_customer_changed: 'Alterou o cliente vinculado', commercial_owner_confirmed: 'Confirmou o proprietário após revenda', customer_registered: 'Cadastrou ou atualizou um cliente', customer_contact_changed: 'Atualizou o contato do cliente', customer_email_changed: 'Alterou o e-mail do cliente', customer_status_changed: 'Alterou o acesso do cliente', staff_access_changed: 'Alterou um acesso da equipe', deadline_retry_requested: 'Solicitou nova tentativa de aviso' };
  return `<div class="review-overlay"><div class="review-modal"><button class="close-review" data-action="close-history" aria-label="Fechar">×</button><h2>Histórico de atividades</h2><div class="activity-list">${historyRows.length ? historyRows.map(row => `<article><strong>${safe(row.actor_name)}</strong><span>${safe(labels[row.action] || row.action)} · ${safe(DATA.apartments.find(u => u.id === row.unit_id)?.label)}</span><small>${safe(formatSessionDate(row.created_at))}${row.details?.module_code ? ' · ' + safe(row.details.module_code) : ''}${row.action === 'unit_status_changed' ? ' · ' + (row.details.active ? 'Ativa' : 'Inativa') : ''}</small></article>`).join('') : '<p>Nenhuma atividade registrada.</p>'}</div></div></div>`;
}
function customerFormHtml() {
  const customer = backend.customers.find(c=>c.id===customerEditingId);
  return `<div class="review-overlay"><div class="review-modal"><button class="close-review" data-action="close-customer" aria-label="Fechar">×</button><h2>${customer ? 'Editar cliente' : 'Cadastrar cliente'}</h2><form id="customer-form"><label>Nome<input name="name" required maxlength="200" autocomplete="name" value="${safe(customer?.name || '')}"></label><label>E-mail da conta<input name="email" type="email" required maxlength="254" autocomplete="email" value="${safe(customer?.email || '')}"></label>${backend.permissionsV2 ? `<label>Telefone<input name="phone" type="tel" maxlength="40" autocomplete="tel" value="${safe(customer?.phone || '')}"></label>` : ''}<p class="session-notice">${customer ? 'A troca de e-mail altera o endereço usado para entrar e recuperar a senha.' : 'O cliente definirá a senha em Primeiro acesso. Para atualizar uma conta existente, informe o mesmo e-mail.'}</p><button type="submit" class="review-primary">Salvar</button></form></div></div>`;
}
function adminPanelHtml() {
  const kind = adminPanel.kind;
  let content = '';
  if(kind==='customers') content = `<p>Desativar a conta bloqueia todas as suas unidades e preserva os dados.</p><div class="activity-list">${backend.customers.map(c=>`<article><strong>${safe(c.name)}</strong><span>${safe(c.email)} · ${safe(c.phone || 'Telefone não informado')} · ${c.active ? 'Ativa' : 'Inativa'}</span><div class="unit-actions"><button data-action="edit-customer" data-id="${safe(c.id)}">Editar</button><button data-action="toggle-customer" data-id="${safe(c.id)}">${c.active ? 'Desativar conta' : 'Ativar conta'}</button></div></article>`).join('') || '<p>Nenhum cliente cadastrado.</p>'}</div>`;
  if(kind==='staff') {
    const edit = adminPanel.edit;
    content = `<p>Revogar acesso preserva o histórico. O Admin principal não pode ser desativado ou rebaixado.</p><div class="activity-list">${adminPanel.rows.map(s=>`<article><strong>${safe(s.name)}</strong><span>${safe(s.email)} · ${s.role==='admin'?'Admin':'Arquiteta'} · ${s.active?'Ativo':'Inativo'}${s.protected?' · Principal':''}</span><button data-action="edit-staff" data-id="${safe(s.user_id)}">Editar</button></article>`).join('')}</div><h3>${edit?'Editar acesso':'Cadastrar acesso'}</h3><form id="staff-form"><label>Nome<input name="name" required maxlength="200" value="${safe(edit?.name || '')}"></label><label>E-mail<input name="email" type="email" required maxlength="254" value="${safe(edit?.email || '')}" ${edit?'readonly':''}></label><label>Perfil<select name="role" ${edit?.protected?'disabled':''}><option value="architect" ${edit?.role==='architect'?'selected':''}>Arquiteta</option><option value="admin" ${edit?.role==='admin'?'selected':''}>Admin</option></select></label><label><input type="checkbox" name="active" ${edit?.active!==false?'checked':''} ${edit?.protected?'disabled':''}> Acesso ativo</label><button class="review-primary" type="submit">Salvar acesso</button>${edit?'<button type="button" data-action="new-staff">Novo cadastro</button>':''}</form>`;
  }
  if(kind==='notifications') content = `<p>Nova tentativa recoloca falhas elegíveis na fila para a próxima verificação automática. Envios já aceitos não são repetidos.</p><div class="activity-list">${adminPanel.rows.map(n=>`<article><strong>${safe(n.unit_code)}</strong><span>${safe(({sent:'Aceito pelo provedor',failed:'Falhou',pending:'Na fila',sending:'Em processamento'})[n.status] || n.status)} · ${n.attempts} tentativa(s)</span><small>${safe(formatSessionDate(n.created_at))}${n.last_error?' · '+safe(n.last_error):''}</small>${n.status==='failed' && n.attempts<5?`<button data-action="retry-notification" data-id="${safe(n.id)}">Solicitar nova tentativa</button>`:''}</article>`).join('') || '<p>Nenhum aviso registrado.</p>'}</div>`;
  return `<div class="review-overlay"><div class="review-modal"><button class="close-review" data-action="close-admin-panel" aria-label="Fechar">×</button><h2>${({customers:'Clientes',staff:'Equipe',notifications:'Avisos de prazo'})[kind]}</h2>${content}</div></div>`;
}
async function runWorkflow(operation, success) {
  if (workflowBusy) return;
  const version = mountVersion;
  workflowBusy = true;
  try { await operation(); if (version !== mountVersion) return; DATA.apartments = backend.units; if (success) showToast(success); render(); }
  catch (error) { if (version === mountVersion) showToast(error.message || 'Não foi possível concluir. Tente novamente.'); }
  finally { if (version === mountVersion) workflowBusy = false; }
}

function fitCatalogCards() {
  document.querySelectorAll('.plant-cards .catalog-card, .material-cards .catalog-card').forEach(card => {
    const copy = card.querySelector('.card-copy');
    const fits = () => copy.scrollHeight <= copy.clientHeight;
    card.style.removeProperty('width');
    let lower = Math.ceil(card.getBoundingClientRect().width);
    let upper = lower;
    card.style.width = `${upper}px`;
    if (fits()) return;
    // Keep the card height fixed; grow only its width until all copy fits.
    do {
      lower = upper;
      upper *= 2;
      card.style.width = `${upper}px`;
    } while (!fits() && upper < 14080);
    while (upper - lower > 2) {
      const middle = Math.ceil((upper + lower) / 2);
      card.style.width = `${middle}px`;
      if (fits()) upper = middle;
      else lower = middle;
    }
    card.style.width = `${upper + 2}px`;
  });
}

function render() {
  app.innerHTML = state.apartmentId ? configuratorHtml() : unitModalHtml();
  if (reviewOpen) app.insertAdjacentHTML('beforeend', reviewHtml());
  if (helpOpen) app.insertAdjacentHTML('beforeend', helpHtml());
  if (managementUnitId) app.insertAdjacentHTML('beforeend', managementHtml());
  if (historyRows) app.insertAdjacentHTML('beforeend', historyHtml());
  if (adminPanel) app.insertAdjacentHTML('beforeend', adminPanelHtml());
  if (customerFormOpen) app.insertAdjacentHTML('beforeend', customerFormHtml());
  if (unavailableUnitId) app.insertAdjacentHTML('beforeend', unavailableUnitHtml());
  fitCatalogCards();
  layoutObserver?.disconnect();
  const screen = document.querySelector('.configurator-screen');
  if (screen && typeof ResizeObserver !== 'undefined') {
    layoutObserver = new ResizeObserver(() => fitCatalogCards());
    layoutObserver.observe(screen);
  }
  if (document.fonts?.status === 'loading') {
    const viewVersion = mountVersion;
    document.fonts.ready.then(() => { if (viewVersion === mountVersion) fitCatalogCards(); });
  }
  bindEvents();
  scheduleDeadlineRefresh();
}

function bindEvents() {
  document.querySelectorAll('[data-unavailable-unit]').forEach(card => {
    card.addEventListener('click', () => openUnavailableUnit(card.dataset.unavailableUnit));
    card.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault(); openUnavailableUnit(card.dataset.unavailableUnit);
      }
    });
  });
  const unavailableOverlay = document.querySelector('.unavailable-unit-overlay');
  unavailableOverlay?.addEventListener('click', event => {
    if (event.target === unavailableOverlay) closeUnavailableUnit();
  });
  unavailableOverlay?.addEventListener('keydown', event => {
    if (event.key === 'Escape') { event.preventDefault(); closeUnavailableUnit(); }
    if (event.key === 'Tab') {
      const buttons = unavailableOverlay.querySelectorAll('button');
      const first = buttons[0], last = buttons[buttons.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });
  document.querySelectorAll('[data-unit]').forEach(btn => btn.addEventListener('click', () => {
    selectApartment(btn.dataset.unit);
  }));
  document.querySelectorAll('[data-action]').forEach(btn => btn.addEventListener('click', () => {
    const action = btn.dataset.action;
    if (action === 'toggle-sidebar') {
      state.sidebarCollapsed = !state.sidebarCollapsed;
      render();
      document.querySelector('[data-action="toggle-sidebar"]')?.focus({ preventScroll: true });
    }
    if (action === 'open-customizer-preview' && canPreview()) {
      ++openingVersion;
      openConfigurator(PREVIEW_APARTMENT.id);
    }
    if (action === 'logout') backend?.onSignOut();
    if (action === 'home' || action === 'change-unit') showApartments();
    if (action === 'review' || action === 'compact-review') {
      const unitId = state.apartmentId;
      const choices = normalizeSelections(state);
      const opening = openingVersion;
      runWorkflow(async () => {
        if (!isPreview()) await backend?.onValidate?.(unitId, choices);
        if (opening !== openingVersion || unitId !== state.apartmentId) return;
        if (JSON.stringify(choices) !== JSON.stringify(normalizeSelections(state))) throw new Error('As escolhas mudaram. Revise novamente.');
        reviewOpen = true;
      });
    }
    if (action === 'close-review') { reviewOpen = false; render(); }
    if (action === 'help') { helpOpen = true; render(); }
    if (action === 'close-help') { helpOpen = false; render(); }
    if (action === 'toggle-unit') {
      const unit = DATA.apartments.find(u => u.id === btn.dataset.unitId);
      runWorkflow(() => backend.onSetActive(unit.id, !unit.active), 'Status da unidade atualizado.');
    }
    if (action === 'manage-unit') { managementUnitId = btn.dataset.unitId; render(); }
    if (action === 'confirm-commercial-owner') {
      const unit = DATA.apartments.find(item => item.id === managementUnitId);
      const customer = backend.customers.find(item => item.id === unit.customerId);
      if (!customer || !window.confirm(`Confirmar ${customer.name} como proprietário da unidade ${unit.label}?`)) return;
      runWorkflow(() => backend.onConfirmCommercialOwner(unit.id, customer.id, unit.commercialReviewRevision),
        'Proprietário confirmado.');
    }
    if (action === 'close-management') { managementUnitId = null; render(); }
    if (action === 'history') runWorkflow(async () => { historyRows = await backend.loadHistory(btn.dataset.unitId || null); });
    if (action === 'close-history') { historyRows = null; render(); }
    if (action === 'new-customer') { customerEditingId = null; customerFormOpen = true; render(); }
    if (action === 'close-customer') { customerFormOpen = false; render(); }
    if (action === 'customers-panel') { adminPanel = {kind:'customers'}; render(); }
    if (action === 'edit-customer') { customerEditingId=btn.dataset.id; customerFormOpen=true; render(); }
    if (action === 'toggle-customer') runWorkflow(async()=>{
      const customer=backend.customers.find(c=>c.id===btn.dataset.id);
      await backend.onSetCustomerActive(customer.id,!customer.active);
    },'Status da conta atualizado.');
    if (action === 'staff-panel') runWorkflow(async()=>{adminPanel={kind:'staff',rows:await backend.loadStaff()};});
    if (action === 'edit-staff') {adminPanel.edit=adminPanel.rows.find(s=>s.user_id===btn.dataset.id);render();}
    if (action === 'new-staff') {adminPanel.edit=null;render();}
    if (action === 'notifications-panel') runWorkflow(async()=>{adminPanel={kind:'notifications',rows:await backend.loadNotifications()};});
    if (action === 'retry-notification') runWorkflow(async()=>{
      await backend.onRetryNotification(btn.dataset.id);
      adminPanel={kind:'notifications',rows:await backend.loadNotifications()};
    },'Nova tentativa solicitada. A fila será verificada pelo agendamento.');
    if (action === 'close-admin-panel') {adminPanel=null;render();}
    if (action === 'close-unavailable') closeUnavailableUnit();
  }));
  document.querySelector('#unit-management-form')?.addEventListener('submit', event => {
    event.preventDefault();
    const form = event.currentTarget;
    const iso = value => value ? new Date(value).toISOString() : null;
    runWorkflow(async () => {
      await backend.onManageUnit(managementUnitId, form.elements.customer.value || null,
        iso(form.elements.deadline.value), Object.fromEntries([...form.querySelectorAll('[data-module-deadline]')]
          .map(input => [input.dataset.moduleDeadline, iso(input.value)])));
      managementUnitId = null;
    }, 'Cadastro e prazos atualizados.');
  });
  document.querySelector('#customer-form')?.addEventListener('submit', event => {
    event.preventDefault();
    const form = event.currentTarget;
    runWorkflow(async () => { await backend.onRegisterCustomer(form.elements.name.value, form.elements.email.value,form.elements.phone?.value || null,customerEditingId); customerFormOpen = false; }, 'Cadastro salvo. Confira o vínculo da unidade em Gerenciar.');
  });
  document.querySelector('#staff-form')?.addEventListener('submit',event=>{
    event.preventDefault(); const form=event.currentTarget;
    const body={name:form.elements.name.value,email:form.elements.email.value,role:form.elements.role.value,active:form.elements.active.checked};
    runWorkflow(async()=>{await backend.onManageStaff(body);adminPanel={kind:'staff',rows:await backend.loadStaff()};},'Acesso da equipe atualizado.');
  });


  document.querySelectorAll('[data-nav]').forEach(btn => btn.addEventListener('click', () => {
    const nav = btn.dataset.nav;
    if (nav === 'plant') { state.module = 'plant'; render(); }
    else if (nav === 'counters') { state.module = 'materials'; state.materialGroup = 'counter'; state.environment = 'cozinha'; render(); }
    else showToast('Este catálogo ainda está em preparação.');
  }));
  document.querySelectorAll('[data-accordion]').forEach(btn => btn.addEventListener('click', () => {
    state.accordions[btn.dataset.accordion] = !state.accordions[btn.dataset.accordion]; render();
  }));
  document.querySelectorAll('[data-plant-group]').forEach(btn => btn.addEventListener('click', () => { state.plantGroup = btn.dataset.plantGroup; render(); }));
  document.querySelectorAll('[data-plant-choice]').forEach(btn => btn.addEventListener('click', () => {
    if (!choiceEnabled(btn.dataset.plantChoice, btn.dataset.value)) return;
    state[btn.dataset.plantChoice] = btn.dataset.value; render();
  }));
  document.querySelectorAll('[data-material-group]').forEach(btn => btn.addEventListener('click', () => { state.materialGroup = btn.dataset.materialGroup; render(); }));
  document.querySelectorAll('[data-material-choice]').forEach(btn => btn.addEventListener('click', () => {
    if (!choiceEnabled(btn.dataset.materialChoice, btn.dataset.value)) return;
    state[btn.dataset.materialChoice] = btn.dataset.value; render();
  }));
  document.querySelectorAll('[data-environment]').forEach(btn => btn.addEventListener('click', () => {
    const env = btn.dataset.environment;
    if (env === 'cozinha') { state.environment = 'cozinha'; if (state.materialGroup === 'service') state.materialGroup = 'counter'; render(); }
    else if (env === 'servico') { state.environment = 'servico'; state.materialGroup = 'service'; render(); }
    else showToast('Ambiente ainda sem catálogo disponível.');
  }));
}
