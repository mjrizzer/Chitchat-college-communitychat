create table public.user_blocks (
 blocker_id uuid not null default auth.uid() references public.profiles on delete cascade,
 blocked_id uuid not null references public.profiles on delete cascade,
 created_at timestamptz not null default now(),primary key(blocker_id,blocked_id),check(blocker_id<>blocked_id)
);
create index blocks_target on public.user_blocks(blocked_id,blocker_id);
create table public.reports (
 id uuid primary key default gen_random_uuid(),reporter_id uuid not null default auth.uid() references public.profiles on delete cascade,
 message_id uuid not null references public.messages on delete cascade,
 category text not null check(category in ('spam','harassment','unsafe','other')),
 created_at timestamptz not null default now(),unique(reporter_id,message_id)
);
create index reports_time on public.reports(created_at desc);
create function public.is_blocked(uid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.user_blocks where (blocker_id=auth.uid() and blocked_id=uid) or (blocked_id=auth.uid() and blocker_id=uid))
$$;
drop policy messages_read on public.messages;
create policy messages_read on public.messages for select to authenticated using(public.can_chat(room_id) and not public.is_blocked(sender_id));
create function public.report_message(mid uuid,reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.messages where id=mid and public.can_chat(room_id) and sender_id<>auth.uid() and not public.is_blocked(sender_id)) then raise exception 'Message unavailable'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,4));
 if (select count(*) from public.reports where reporter_id=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception 'Daily reporting limit reached'; end if;
 insert into public.reports(reporter_id,message_id,category) values(auth.uid(),mid,reason) on conflict(reporter_id,message_id) do nothing;
end $$;
create or replace function public.push_tokens(nid uuid) returns table(token text) language sql stable security definer set search_path='' as $$
 select d.token from public.notifications n join public.profiles p on p.id=n.user_id join auth.users u on u.id=p.id
 join public.room_members m on m.room_id=n.room_id and m.user_id=n.user_id join public.rooms r on r.id=m.room_id join public.device_tokens d on d.user_id=n.user_id
 where n.id=nid and p.push_enabled and not p.suspended and not m.muted and (u.is_anonymous or u.email_confirmed_at is not null)
 and (r.is_lounge or r.expires_at>now()) and d.updated_at>now()-interval '30 days'
 and not exists(select 1 from public.user_blocks b where (b.blocker_id=n.user_id and b.blocked_id=n.actor_id) or (b.blocker_id=n.actor_id and b.blocked_id=n.user_id))
$$;
alter table public.user_blocks enable row level security;
alter table public.reports enable row level security;
create policy blocks_read on public.user_blocks for select to authenticated using(blocker_id=auth.uid() and public.active_user());
create policy blocks_insert on public.user_blocks for insert to authenticated with check(blocker_id=auth.uid() and public.active_user());
create policy blocks_delete on public.user_blocks for delete to authenticated using(blocker_id=auth.uid() and public.active_user());
create policy reports_own on public.reports for select to authenticated using(reporter_id=auth.uid() and public.active_user());
-- Moderators review reports through the trusted Supabase dashboard/service only.
-- Report deletion cascades with the message to preserve temporary-chat deletion.
revoke all on public.user_blocks,public.reports from anon,authenticated;
grant select on public.user_blocks,public.reports to authenticated;
grant insert(blocked_id),delete on public.user_blocks to authenticated;
grant all on public.user_blocks,public.reports to service_role;
revoke execute on function public.is_blocked(uuid),public.report_message(uuid,text) from public,anon;
grant execute on function public.is_blocked(uuid),public.report_message(uuid,text) to authenticated;
