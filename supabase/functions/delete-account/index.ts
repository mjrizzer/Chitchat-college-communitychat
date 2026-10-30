import { createClient } from 'npm:@supabase/supabase-js@2';
Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const jwt = request.headers.get('Authorization')?.replace(/^Bearer /, '');
  if (!jwt) return new Response('Unauthorized', { status: 401 });
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: { user }, error } = await db.auth.getUser(jwt);
  if (error || !user) return new Response('Unauthorized', { status: 401 });
  try {
    const { error: deleteError } = await db.auth.admin.deleteUser(user.id);
    if (deleteError) throw deleteError;
    return Response.json({ deleted: true });
  } catch (_) {
    return Response.json({ error: 'Deletion could not finish. Retry safely or contact support.' }, { status: 500 });
  }
});
