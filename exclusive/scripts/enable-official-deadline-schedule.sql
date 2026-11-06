-- Run only after explicit approval and after the function is deployed/tested.
-- Target: grfmiuopojbxxbdymqax. No new application tables.
-- User stores the SAME random 32+ character token as:
-- 1. Edge Function secret DEADLINE_REMINDER_TOKEN
-- 2. Vault secret citypark_deadline_reminder_token_v2
-- Never paste the actual secret into this SQL or a saved SQL snippet.
begin;
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
do $guard$
begin
 if (select count(*) from vault.decrypted_secrets
     where name='citypark_deadline_reminder_token_v2' and length(decrypted_secret)>=32) <> 1 then
   raise exception 'Store exactly one valid scheduler token in Vault first';
 end if;
 if exists(select 1 from cron.job where jobname='citypark-deadline-reminders') then
   raise exception 'Schedule already exists; inspect instead of duplicating it';
 end if;
end;
$guard$;
select cron.schedule('citypark-deadline-reminders','*/10 * * * *', $job$
 select net.http_post(
   url:='https://grfmiuopojbxxbdymqax.supabase.co/functions/v1/deadline-reminders',
   headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' ||
     (select decrypted_secret from vault.decrypted_secrets where name='citypark_deadline_reminder_token_v2')),
   body:='{}'::jsonb, timeout_milliseconds:=120000
 );
$job$);
commit;
select jobname,schedule,active from cron.job where jobname='citypark-deadline-reminders';
