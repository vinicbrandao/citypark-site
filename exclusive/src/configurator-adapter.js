// Database bridge for the approved configurator layout in ../app.js.
// Choices are transient; only access and administrative actions are persisted.
const CATALOG = {
  socialPlant: { module: 'planta', group: 'DEMO-AREA-SOCIAL', values: {
    'social-original': 'padrao',
    'social-standard': 'euroglass',
    'social-veranda': 'integrada',
    'social-full': 'ilha'
  } },

  suitePlant: { module: 'planta', group: 'DEMO-SUITE-MASTER', values: {
    'suite-standard': 'padrao',
    'suite-closet': 'closet',
    'suite-office': 'gabinete'
  } },

  counter: { module: 'bancadas', group: 'DEMO-BANCADA', values: {
    'counter-standard': 'padrao',
    'counter-extended': 'estendida'
  } },

  stone: { module: 'bancadas', group: 'DEMO-GRANITO', values: {
    'sao-marco': 'sao-marco',
    bellagio: 'bellagio'
  } },

  rodamao: { module: 'bancadas', group: 'DEMO-RODAMAO', values: {
    padrao: 'padrao',
    '60': '60'
  } },

  service: { module: 'bancadas', group: 'DEMO-SERVICO', values: {
    'service-no': 'padrao',
    'service-yes': 'bancada'
  } }
};

const check = result => { if (result.error) throw result.error; return result.data; };
const formatDeadline = value => value ? new Intl.DateTimeFormat('pt-BR', {
  timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit'
}).format(new Date(value)) : 'Sem prazo';

export async function createConfiguratorAdapter({ client, staffRole, onSignOut, permissionsV2 = false }) {
  const rows = {};
  const adapter = {
    staffRole, onSignOut, permissionsV2, units: [], customers: [], modules: [],
    canEdit, isOptionAvailable, defaultsForUnit, onValidate, onOpen, refresh,
    onSetActive: (id, active) => mutate('set_unit_active', { p_unit_id: id, p_active: active }),
    onSetDeadline: (id, date) => mutate('set_unit_deadline', { p_unit_id: id, p_closes_at: date }),
    onSetModuleDeadline: (id, module, date) => mutate('set_module_deadline', {
      p_unit_id: id, p_module_code: module, p_closes_at: date
    }),
    onSetCustomer: (id, customer) => mutate('set_unit_customer', { p_unit_id: id, p_customer_id: customer }),
    onManageUnit: (id, customer, date, modules) => mutate('manage_unit', {
      p_unit_id: id, p_customer_id: customer, p_closes_at: date, p_module_deadlines: modules
    }),
    onConfirmCommercialOwner: (id, customer, revision) => mutate('confirm_commercial_owner', {
      p_unit_id: id, p_customer_id: customer, p_revision: revision
    }),
    onRegisterCustomer: async (name, email, phone = null, customerId = null) => {
      await invoke('admin-customer', { name, email,
        ...(permissionsV2 ? { phone, customerId, action: customerId ? 'update' : 'create' } : {}) });
      await refresh();
    },
    onSetCustomerActive: (id, active) => mutate('set_customer_active', {p_customer_id:id,p_active:active}),
    loadStaff: async () => check(await client.rpc('list_staff_accounts')),
    onManageStaff: async body => {
      await invoke('admin-staff', body);
    },
    loadNotifications: async () => check(await client.from('deadline_notifications')
      .select('id,unit_code,status,attempts,last_error,created_at,sent_at').order('created_at',{ascending:false}).limit(100)),
    onRetryNotification: id => mutate('retry_deadline_notification',{p_id:id}),
    loadHistory
  };
  async function invoke(name, body) {
    const result = await client.functions.invoke(name,{body});
    let message=result.data?.error;
    if(result.error) {
      try {message=(await result.error.context.json()).error;} catch { /* No server response body. */ }
    }
    if(result.error || message) throw new Error(typeof message==='string' ? message : 'Não foi possível concluir a operação. Confira o serviço administrativo.');
    return result.data;
  }
  async function refresh() {
    const queries = {
      units: staffRole
        ? client.from('units').select('id,code,tower,tower_code,floor_label,termination,typology,area_m2,customization_closes_at,active,customization_status').order('tower_code').order('floor_number').order('termination_code').order('code')
        : client.rpc('list_customer_unit_cards'),
      customers: client.from('customers').select(permissionsV2 ? 'id,name,email,phone,active' : 'id,name,email').order('name'),
      links: client.from('customer_units').select('unit_id,customer_id').eq('active', true).eq('ownership_role', 'owner'),
      assignments: client.from('unit_base_plan_assignments').select('unit_id,base_plan_id'),
      plans: client.from('base_plans').select('id,name,status'),
      modules: client.from('customization_modules').select('code,name,sort_order').order('sort_order'),
      windows: client.from('unit_module_windows').select('unit_id,module_code,opens_at,closes_at,status'),
      groups: client.from('customization_groups').select('id,code,module_code,status,required_for_submission'),
      options: client.from('customization_options').select('id,group_id,code,status'),
      availability: client.from('base_plan_option_availability').select('base_plan_id,option_id'),
      defaults: client.from('base_plan_option_defaults').select('base_plan_id,group_id,option_id'),
      exclusions: client.from('base_plan_option_exclusions').select('base_plan_id,first_option_id,second_option_id'),
      requirements: client.from('base_plan_option_requirements').select('base_plan_id,option_id,required_option_id')
    };
    const entries = Object.entries(queries);
    const results = await Promise.all(entries.map(([, query]) => query));
    entries.forEach(([key], index) => { rows[key] = check(results[index]); });
    const commercialReviews = new Map();
    if (staffRole === 'admin') {
      const result = await client.rpc('list_commercial_owner_reviews');
      // Older environments can still use the existing administration screens.
      if (result.error?.code !== 'PGRST202') {
        for (const review of check(result)) commercialReviews.set(review.unit_id, review.revision);
      }
    }
    adapter.customers = rows.customers;
    adapter.modules = rows.modules;
    adapter.units = rows.units.map(unit => {
      const windows = rows.windows.filter(w => w.unit_id === unit.id);
      const customerId = rows.links.find(link => link.unit_id === unit.id)?.customer_id;
      return {
        id: unit.id, label: unit.code, tower: unit.tower, towerCode: unit.tower_code,
        floor: unit.floor_label, termination: unit.termination, type: unit.typology, areaM2: unit.area_m2,
        active: unit.active, customizationStatus: unit.customization_status,
        commercialReviewRevision: commercialReviews.get(unit.id),
        customizationClosesAt: unit.customization_closes_at,
        customizationDeadline: formatDeadline(unit.customization_closes_at),
        plantDeadline: formatDeadline(windows.find(w => w.module_code === 'planta')?.closes_at),
        moduleWindows: windows, customerId, customer: rows.customers.find(c => c.id === customerId),
        basePlanName: rows.plans.find(p => p.id === planId(unit.id))?.name || 'Não atribuída',
        situation: ['09A', '10A'].includes(unit.termination)
          ? `${import.meta.env.BASE_URL}assets/situacao/${unit.termination}.jpg` : null
      };
    });
    return adapter;
  }
  function planId(unitId) { return rows.assignments.find(row => row.unit_id === unitId)?.base_plan_id; }
  function group(key) { return rows.groups.find(row => row.code === CATALOG[key].group && row.module_code === CATALOG[key].module); }
  function option(key, value) { return rows.options.find(row => row.group_id === group(key)?.id && row.code === CATALOG[key].values[value]); }
  function defaultsForUnit(unitId) {
    const defaults = {};
    for (const [key, definition] of Object.entries(CATALOG)) {
      const selected = rows.defaults.find(row => row.base_plan_id === planId(unitId) && row.group_id === group(key)?.id);
      const code = rows.options.find(row => row.id === selected?.option_id)?.code;
      defaults[key] = Object.entries(definition.values).find(([, value]) => value === code)?.[0] || null;
    }
    return defaults;
  }
  function availableForPlan(unitId, key, value) {
    const selected = option(key, value);
    return Boolean(selected?.status === 'active' && group(key)?.status === 'active' && rows.availability.some(
      row => row.base_plan_id === planId(unitId) && row.option_id === selected.id
    ));
  }
  function isOptionAvailable(unitId, key, value, selections = defaultsForUnit(unitId)) {
    if (!availableForPlan(unitId, key, value)) return false;
    const candidate = { ...selections, [key]: value };
    const ids = new Set(Object.keys(CATALOG).map(k => option(k, candidate[k])?.id).filter(Boolean));
    const plan = planId(unitId);
    return !rows.exclusions.some(rule => rule.base_plan_id === plan && ids.has(rule.first_option_id) && ids.has(rule.second_option_id)) &&
      !rows.requirements.some(rule => rule.base_plan_id === plan && ids.has(rule.option_id) && !ids.has(rule.required_option_id));
  }
  function canEdit(unitId, module) {
    const unit = rows.units.find(row => row.id === unitId);
    const now = Date.now();
    if (!unit || (!staffRole && !unit.active) || !planId(unitId) ||
      (unit.customization_closes_at && now >= Date.parse(unit.customization_closes_at))) return false;
    const window = rows.windows.find(row => row.unit_id === unitId && row.module_code === module);
    return !window || (window.status === 'active' && now >= Date.parse(window.opens_at) && now < Date.parse(window.closes_at));
  }
  async function onValidate(unitId, selections) {
    const mapped = {};
    for (const key of Object.keys(CATALOG)) {
      if (!availableForPlan(unitId, key, selections[key])) throw new Error('O catálogo desta unidade ainda não está completo.');
      mapped[group(key).id] = option(key, selections[key]).id;
    }
    try { return check(await client.rpc('validate_unit_session', { p_unit_id: unitId, p_selections: mapped })); }
    catch (error) { throw explain(error); }
  }
  async function onOpen(unitId) {
    try { check(await client.rpc('record_unit_access', { p_unit_id: unitId })); }
    catch (error) { throw explain(error); }
  }
  async function mutate(name, params) {
    try { check(await client.rpc(name, params)); await refresh(); }
    catch (error) { throw explain(error); }
  }
  async function loadHistory(unitId = null) {
    let query = client.from('unit_activity_events')
      .select('id,unit_id,actor_name,actor_role,action,details,created_at').order('id', { ascending: false }).limit(100);
    if (unitId) query = query.eq('unit_id', unitId);
    return check(await query);
  }
  function explain(error) {
    if (error?.message === 'Only admin can reopen completed unit') return new Error('Somente o Admin pode reativar uma unidade concluída.');
    if (error?.message === 'Customization deadline closed') return new Error('O prazo encerrou. Um Admin precisa reabri-lo para permitir alterações.');
    if (error?.message === 'Incompatible session choices') return new Error('Estas escolhas não são compatíveis entre si.');
    if (error?.code === '42501') return new Error('Ação não permitida para este perfil ou unidade.');
    if (error?.code === '22023') return new Error('Confira o cadastro e as opções disponíveis para esta unidade.');
    return new Error(error?.message || 'Não foi possível concluir a operação.');
  }
  return refresh();
}
