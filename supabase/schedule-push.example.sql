-- Run only after deploying push-dispatch and setting its PUSH_WORKER_SECRET.
-- Substitute placeholders in your private SQL editor, never commit real values.
create extension if not exists pg_net with schema extensions;
select vault.create_secret('https://YOUR_PROJECT.supabase.co','chitchat_project_url');
select vault.create_secret('YOUR_RANDOM_WORKER_SECRET','chitchat_worker_secret');
select cron.schedule('chitchat-push','* * * * *', $job$
 select net.http_post(
  url := (select decrypted_secret from vault.decrypted_secrets where name='chitchat_project_url')||'/functions/v1/push-dispatch',
  headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='chitchat_worker_secret')),
  body := '{}'::jsonb
 );
$job$);
