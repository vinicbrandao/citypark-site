// Old browser/worker scenarios delete fixtures from the shared local database.
// The production-permissions model deliberately forbids those deletions.
export async function requireLegacyFixtureCleanup(service) {
  const {error}=await service.from('customers').select('phone').limit(0);
  if(!error) throw new Error('Este roteiro legado apaga fixtures e não pode usar o modelo com histórico imutável. Use scripts/test-official-bootstrap-local.mjs e scripts/test-permissions-upgrade-local.mjs, que trabalham em bancos temporários.');
  if(!['42703','PGRST204'].includes(error.code)) throw new Error('Não foi possível conferir o modelo local antes do teste. Nenhuma fixture foi criada.');
}
