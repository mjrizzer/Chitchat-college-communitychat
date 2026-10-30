import { PGlite } from '@electric-sql/pglite';
import { readFile,readdir } from 'node:fs/promises';

// Test-only Supabase auth schema fixture in a real WASM PostgreSQL engine.
// Cron scheduling and Realtime publication wiring require deployed Supabase.
const db = new PGlite();
try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role bypassrls;
    create schema auth;
    create table auth.users(id uuid primary key,aud text,role text,is_anonymous boolean default false,email_confirmed_at timestamptz,created_at timestamptz,updated_at timestamptz);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    grant usage on schema public,auth to anon,authenticated,service_role;
    grant execute on function auth.uid() to anon,authenticated,service_role;
  `);
  for(const file of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort()){
  let migration = await readFile(new URL('../supabase/migrations/'+file, import.meta.url), 'utf8');
  migration = migration.replace(/^create extension[^;]+;\s*$/gm, '');
  migration = migration.replace(/^alter publication[^;]+;\s*$/gm, '');
  migration = migration.replace(/select cron\.schedule\([\s\S]*?\$job\$\);/g, '');
  await db.exec(migration);
  }
  await db.exec(await readFile(new URL('../supabase/tests/security.sql', import.meta.url), 'utf8'));
  console.log('PASS: PostgreSQL migration, RLS authorization, expiry, creator membership and deletion assertions.');
  console.log('NOT TESTED: hosted Supabase Auth, Cron scheduling, Realtime transport or Firebase delivery.');
} catch (error) {
  console.error('SQL verification failed:', error.message);
  process.exitCode = 1;
} finally { await db.close(); }
