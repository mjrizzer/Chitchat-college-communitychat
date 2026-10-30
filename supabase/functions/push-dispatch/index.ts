import { createClient } from 'npm:@supabase/supabase-js@2';
import { GoogleAuth } from 'npm:google-auth-library@10';
import { timingSafeEqual } from 'node:crypto';

// Invoke only from a trusted scheduler. This endpoint accepts no user-selected
// tokens, recipients, titles or content. All jobs originate in database triggers.
Deno.serve(async (request) => {
  const expected = Deno.env.get('PUSH_WORKER_SECRET');
  const provided = request.headers.get('Authorization')?.replace(/^Bearer /, '') ?? '';
  const encoder = new TextEncoder();
  if (!expected || encoder.encode(provided).length !== encoder.encode(expected).length ||
      !timingSafeEqual(encoder.encode(provided), encoder.encode(expected))) {
    return new Response('Unauthorized', { status: 401 });
  }
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  try {
    const credentials = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}');
    if (!credentials.project_id || !credentials.private_key || !credentials.client_email) {
      return new Response('Firebase server configuration missing', { status: 503 });
    }
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const auth = new GoogleAuth({ credentials, scopes: ['https://www.googleapis.com/auth/firebase.messaging'] });
    const accessToken = await auth.getAccessToken();
    const { data: jobs, error } = await db.rpc('claim_push_jobs');
    if (error) throw error;
    let processed = 0;
    for (const job of jobs ?? []) {
      // Reevaluate membership, expiry, blocks, suspension and mute immediately
      // before delivery, invalidating jobs whose recipients are no longer eligible.
      const { data: devices, error: recipientError } = await db.rpc('push_tokens', { nid: job.id });
      if (recipientError) throw recipientError;
      let retry = false;
      for (const device of devices ?? []) {
        const response = await fetch(`https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: {
            fid: device.token,
            notification: { title: 'ChitChat', body: 'There’s a new message in your chat.' },
            data: { notification_id: job.id, room_id: job.room_id },
            android: { priority: 'normal', ttl: '0s', notification: { tag: job.id } },
          } }),
          signal: AbortSignal.timeout(10000),
        });
        if (!response.ok) {
          const result = await response.json();
          const unregistered = result.error?.details?.some((d: { errorCode?: string }) => d.errorCode === 'UNREGISTERED');
          if (unregistered) await db.from('device_tokens').delete().eq('token', device.token);
          else retry = true; // Invalid payload/configuration must not erase tokens.
        }
      }
      const { error: updateError } = await db.from('notifications').update(retry ? {
        locked_until: null, available_at: new Date(Date.now() + 60000 * 2 ** job.attempts).toISOString(),
      } : { delivered_at: new Date().toISOString(), locked_until: null }).eq('id', job.id);
      if (updateError) throw updateError;
      processed++;
    }
    await db.from('device_tokens').delete().lt('updated_at', new Date(Date.now() - 30 * 86400000).toISOString());
    return Response.json({ processed });
  } catch (_) {
    // Never log tokens, private messages, OAuth responses or service-account data.
    return Response.json({ error: 'Dispatch failed; queued jobs can be retried.' }, { status: 500 });
  }
});
