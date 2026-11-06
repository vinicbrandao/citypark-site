// Fonte operacional para a integração. Mantida separada dos gatilhos comerciais.
function lerUnidadesComerciaisParaExclusive_() {
  const resposta = UrlFetchApp.fetch(
    'https://firestore.googleapis.com/v1/' + FIRESTORE_DOCUMENT_BASE + ':runQuery',
    {
      method: 'post',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
      payload: JSON.stringify({ structuredQuery: {
        from: [{ collectionId: 'unidades' }],
        select: { fields: ['unidade', 'status', 'destinacao', 'vendidoEm'].map(fieldPath => ({ fieldPath })) }
      } }),
      muteHttpExceptions: true
    }
  );
  if (resposta.getResponseCode() !== 200) {
    throw new Error('Consulta comercial falhou. HTTP ' + resposta.getResponseCode());
  }
  const resultados = JSON.parse(resposta.getContentText());
  if (!Array.isArray(resultados) || resultados.some(item => item.error || item.skippedResults)) {
    throw new Error('Resposta comercial inválida ou incompleta.');
  }

  const unidades = resultados.filter(item => item.document).map(({ document }) => {
    const campos = document.fields || {};
    return {
      documentoId: document.name.split('/').pop(),
      unidade: campos.unidade?.stringValue ?? null,
      status: campos.status?.stringValue ?? null,
      destinacao: campos.destinacao?.stringValue ?? null,
      vendidoEm: campos.vendidoEm?.timestampValue ?? null
    };
  });
  if (!unidades.length) throw new Error('A consulta comercial retornou zero unidades.');
  return unidades;
}

// O envio manual força a leitura completa, inclusive na primeira configuração.
function sincronizarInventarioExclusive() {
  return executarInventarioExclusive_(true);
}

function verificarInventarioExclusive() {
  return executarInventarioExclusive_(false);
}

function lerVersaoInventarioExclusive_() {
  const url = 'https://firestore.googleapis.com/v1/' + FIRESTORE_DOCUMENT_BASE
    + '/disponibilidade_publica/estoque?mask.fieldPaths=schemaVersao';
  const response = UrlFetchApp.fetch(url, {
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
    muteHttpExceptions: true
  });
  if (response.getResponseCode() !== 200) {
    throw new Error('Consulta do marcador comercial falhou. HTTP ' + response.getResponseCode());
  }
  const version = JSON.parse(response.getContentText()).updateTime;
  if (!version) throw new Error('Marcador comercial sem versão.');
  return version;
}

function executarInventarioExclusive_(forcar) {
  // Os gatilhos comerciais usam o lock do script. O lock do usuário evita
  // sobreposição das execuções do Exclusive sem disputar aquele lock.
  const lock = LockService.getUserLock();
  if (!lock.tryLock(1000)) return { ignorado: 'execução em andamento' };
  try {
    const props = PropertiesService.getScriptProperties();
    const endpoint = props.getProperty('EXCLUSIVE_INVENTORY_ENDPOINT');
    const token = props.getProperty('EXCLUSIVE_INVENTORY_TOKEN');
    if (!endpoint || !/^https:\/\/[a-z0-9-]+\.supabase\.co\/functions\/v1\/commercial-inventory$/.test(endpoint)
        || !token || token.length < 32) {
      throw new Error('Configure o endpoint HTTPS e o token dedicado do inventário.');
    }

    const version = lerVersaoInventarioExclusive_();
    const lastVersion = props.getProperty('EXCLUSIVE_INVENTORY_VERSION');
    const lastSync = Number(props.getProperty('EXCLUSIVE_INVENTORY_LAST_SYNC'));
    if (!forcar && version === lastVersion && Date.now() - lastSync < 60 * 60 * 1000) {
      return { ignorado: 'sem mudanças' };
    }

    const capturedAt = new Date().toISOString();
    const units = lerUnidadesComerciaisParaExclusive_();
    const codes = units.map(unit => {
      const parts = unit.unidade?.trim().toUpperCase().match(/^(\d{3,4})\s*([AB])$/);
      return parts ? parts[1] + parts[2] : null;
    });
    if (units.length !== 389 || codes.includes(null) || new Set(codes).size !== units.length) {
      throw new Error('Inventário comercial inesperado. Confira quantidade, códigos e duplicidades.');
    }

    const response = UrlFetchApp.fetch(endpoint, {
      method: 'post',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + token },
      payload: JSON.stringify({ capturedAt, units }),
      followRedirects: false,
      muteHttpExceptions: true
    });
    if (response.getResponseCode() !== 200) {
      throw new Error('Envio do inventário falhou. HTTP ' + response.getResponseCode());
    }
    const result = JSON.parse(response.getContentText());
    if (result.saved !== true || result.matched !== units.length) {
      throw new Error('O receptor não confirmou o inventário completo.');
    }
    props.setProperties({
      EXCLUSIVE_INVENTORY_VERSION: version,
      EXCLUSIVE_INVENTORY_LAST_SYNC: String(Date.now())
    });
    console.log(JSON.stringify(result));
    return result;
  } finally {
    lock.releaseLock();
  }
}

function instalarGatilhoInventarioExclusive() {
  const handler = 'verificarInventarioExclusive';
  const triggers = ScriptApp.getProjectTriggers();
  if (triggers.some(trigger => trigger.getHandlerFunction() === handler)) return;
  if (triggers.some(trigger => trigger.getHandlerFunction() === 'sincronizarInventarioExclusive')) {
    throw new Error('Já existe um gatilho para o envio completo. Confira antes de instalar outro.');
  }
  ScriptApp.newTrigger(handler).timeBased().everyMinutes(1).create();
}