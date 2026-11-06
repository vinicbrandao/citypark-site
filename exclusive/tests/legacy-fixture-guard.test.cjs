const {test}=require('node:test');
const assert=require('node:assert/strict');
const load=()=>import('../scripts/require-legacy-fixture-cleanup.mjs');
const service=error=>({from(){return {select(){return this;},limit(){return Promise.resolve({error});}};}});
test('legacy cleanup scripts refuse fixtures in the immutable model before any account writes',async()=>{const {requireLegacyFixtureCleanup}=await load();await assert.rejects(requireLegacyFixtureCleanup(service(null)),/histórico imutável/);});
test('legacy cleanup scripts only accept a positively identified old schema',async()=>{const {requireLegacyFixtureCleanup}=await load();await requireLegacyFixtureCleanup(service({code:'42703'}));});
test('legacy cleanup scripts fail closed when the schema cannot be verified',async()=>{const {requireLegacyFixtureCleanup}=await load();await assert.rejects(requireLegacyFixtureCleanup(service({code:'NETWORK_ERROR'})),/Nenhuma fixture/);});
