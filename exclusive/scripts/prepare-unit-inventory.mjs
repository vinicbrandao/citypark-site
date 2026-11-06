import {mkdirSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

// Labels verified across the four continuous screenshots supplied on 30/10.
// Commercial colors carry no meaning for Exclusive and are intentionally absent.
export const units = ['A','B'].flatMap(tower =>
  Array.from({length:tower==='A'?21:20},(_,i)=>i+2).flatMap(floor =>
    Array.from({length:tower==='A'&&floor!==22?10:9},(_,i)=>{
      const termination=String(i+1).padStart(2,'0');
      return {code:`${floor}${termination}${tower}`,tower,floor,termination};
    })));
if(units.length!==389 || new Set(units.map(u=>u.code)).size!==389 || units.filter(u=>u.tower==='A').length!==209)throw Error('Invalid inventory');

export const body=`
lock table public.units in share row exclusive mode;
create temp table citypark_expected_units(code text primary key,tower text,floor_number integer,termination text,
 unique(tower,floor_number,termination)) on commit drop;
insert into citypark_expected_units values
${units.map(u=>`('${u.code}','${u.tower}',${u.floor},'${u.termination}')`).join(',\n')};
do $guard$ begin
 if exists(select 1 from public.units u left join citypark_expected_units e on e.code=u.code where e.code is null) then
   raise exception 'Existing unit outside the approved inventory; stop and reconcile';end if;
 if exists(select 1 from public.units u join citypark_expected_units e on e.code=u.code
   where (u.tower_code is not null and u.tower_code<>e.tower)
     or (u.floor_number is not null and u.floor_number<>e.floor_number)
     or (u.termination_code is not null and u.termination_code<>e.termination)) then
   raise exception 'Existing unit location conflicts with the approved inventory';end if;
end $guard$;
create temp table citypark_units_before on commit drop as select id,to_jsonb(u) as snapshot from public.units u;
create temp table citypark_related_before on commit drop as select jsonb_build_object(
 'auth',(select count(*) from auth.users),'customers',(select count(*) from public.customers),
 'links',(select count(*) from public.customer_units),'accounts',(select count(*) from public.customer_users),
 'staff',(select count(*) from public.staff_users),'notices',(select count(*) from public.deadline_notifications),
 'plans',(select count(*) from public.unit_base_plan_assignments),'windows',(select count(*) from public.unit_module_windows),
 'history',(select count(*) from public.unit_activity_events)) as counts;
insert into public.units(code,tower,tower_code,floor_label,floor_number,termination,termination_code,typology,active,
 area_m2,customization_closes_at,customization_status)
select code,tower,tower,floor_number::text||'º andar',floor_number,termination,termination,'A confirmar',false,
 null,null,'pending' from citypark_expected_units e
where not exists(select 1 from public.units u where u.code=e.code)
order by tower,floor_number,termination
on conflict(code) do nothing;
do $verify$ begin
 if (select count(*) from public.units)<>389
  or (select count(*) from public.units where tower_code='A')<>209
  or (select count(*) from public.units where tower_code='B')<>180 then raise exception 'Inventory totals failed';end if;
 if exists(select 1 from citypark_units_before b left join public.units u on u.id=b.id where to_jsonb(u) is distinct from b.snapshot) then
  raise exception 'Existing unit was modified';end if;
 if exists(select 1 from public.units u where not exists(select 1 from citypark_units_before b where b.id=u.id)
  and (u.active or u.typology<>'A confirmar' or u.area_m2 is not null or u.customization_closes_at is not null or u.customization_status<>'pending')) then
  raise exception 'New units must be empty and inactive';end if;
 if (select counts from citypark_related_before) is distinct from jsonb_build_object(
 'auth',(select count(*) from auth.users),'customers',(select count(*) from public.customers),
 'links',(select count(*) from public.customer_units),'accounts',(select count(*) from public.customer_users),
 'staff',(select count(*) from public.staff_users),'notices',(select count(*) from public.deadline_notifications),
 'plans',(select count(*) from public.unit_base_plan_assignments),'windows',(select count(*) from public.unit_module_windows),
 'history',(select count(*) from public.unit_activity_events)) then raise exception 'Related records changed';end if;
end $verify$;
`;
export const sql=`-- Authorized inventory load: official grfmiuopojbxxbdymqax. No permission changes, seed accounts or schema migrations.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
${body}
commit;
select tower_code as torre,count(*) as unidades,count(*) filter(where not active) as inativas,
 count(*) filter(where area_m2 is null) as sem_area from public.units group by tower_code order by tower_code;
`;
export function prepareInventory(){
 const dir=new URL('../outputs/deployment/grfmiuopojbxxbdymqax/',import.meta.url);mkdirSync(dir,{recursive:true});
 writeFileSync(new URL('unit-inventory.sql',dir),sql);
 writeFileSync(new URL('unit-inventory-manifest.json',dir),JSON.stringify({total:389,A:209,B:180,sha256:createHash('sha256').update(sql).digest('hex'),units},null,2)+'\n');
 console.log('Inventário preparado: 389 unidades (209 A + 180 B). Nenhuma conexão remota.');
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))prepareInventory();
