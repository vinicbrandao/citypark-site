import { readFileSync } from 'node:fs';
import { units } from '../exclusive/scripts/prepare-unit-inventory.mjs';

function codigoUnidade(valor) {
  if (typeof valor !== 'string') return null;
  const partes = valor.trim().toUpperCase().match(/^(\d{3,4})\s*([AB])$/);
  return partes ? partes[1] + partes[2] : null;
}

function compararInventario(comercial) {
  if (!Array.isArray(comercial) || !comercial.length) {
    throw new Error('Informe um inventário comercial com pelo menos uma unidade.');
  }
  const codigosExclusive = new Set(units.map(unit => unit.code));
  const registros = new Map();
  const invalidos = [];
  const semCorrespondenciaExclusive = [];
  for (const unidade of comercial) {
    const codigo = codigoUnidade(unidade?.unidade);
    if (!codigo) {
      invalidos.push(unidade?.documentoId ?? null);
      continue;
    }
    const grupo = registros.get(codigo) ?? [];
    grupo.push(unidade);
    registros.set(codigo, grupo);
    if (!codigosExclusive.has(codigo)) semCorrespondenciaExclusive.push(codigo);
  }

  const ambiguos = [];
  const semCorrespondenciaComercial = [];
  const correspondencias = [];
  for (const { code: codigo } of units) {
    const grupo = registros.get(codigo) ?? [];
    if (grupo.length === 0) {
      semCorrespondenciaComercial.push(codigo);
    } else if (grupo.length > 1) {
      ambiguos.push(codigo);
    } else {
      const { documentoId, status, destinacao } = grupo[0];
      correspondencias.push({ codigo, documentoId, status, destinacao });
    }
  }

  return {
    totalEsperadoExclusive: units.length,
    correspondencias,
    semCorrespondenciaComercial,
    semCorrespondenciaExclusive: [...new Set(semCorrespondenciaExclusive)].sort(),
    ambiguos,
    invalidos
  };
}

const arquivo = process.argv[2];
if (!arquivo) throw new Error('Uso: node scripts/conferir-unidades-comercial.mjs <inventario-comercial.json>');
const comercial = JSON.parse(readFileSync(arquivo, 'utf8').replace(/^\uFEFF/, ''));
console.log(JSON.stringify(compararInventario(comercial), null, 2));
