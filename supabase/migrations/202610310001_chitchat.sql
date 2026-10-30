-- Fresh standalone ChitChat backend. No college verification, feed or events.
create extension if not exists pgcrypto;
create extension if not exists pg_cron with schema pg_catalog;

create table public.profiles (
 id uuid primary key references auth.users on delete cascade,
 name text not null default 'Guest' check(length(trim(name)) between 1 and 60),
 push_enabled boolean not null default true,
 suspended boolean not null default false,
 created_at timestamptz not null default now()
);
create table public.rooms (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(trim(name)) between 3 and 60),
 owner_id uuid references public.profiles on delete cascade,
 is_lounge boolean not null default false,
 created_at timestamptz not null default now(),expires_at timestamptz,
 check((is_lounge and expires_at is null and owner_id is null) or (not is_lounge and expires_at is not null and expires_at=created_at+interval '1 hour' and owner_id is not null))
);
create unique index one_lounge on public.rooms(is_lounge) where is_lounge;
create index rooms_expiry on public.rooms(expires_at) where not is_lounge;
insert into public.rooms(id,name,is_lounge) values('00000000-0000-4000-8000-000000000001','Community chat',true);
create table public.room_members (
 room_id uuid references public.rooms on delete cascade,
 user_id uuid default auth.uid() references public.profiles on delete cascade,
 muted boolean not null default false,joined_at timestamptz not null default now(),
 primary key(room_id,user_id)
);
create index room_members_user on public.room_members(user_id);
create table public.messages (
 id uuid primary key,room_id uuid not null references public.rooms on delete cascade,
 sender_id uuid not null default auth.uid() references public.profiles on delete cascade,
 body text not null check(length(trim(body)) between 1 and 2000),
 created_at timestamptz not null default clock_timestamp()
);
create index messages_room_time on public.messages(room_id,created_at desc,id);
create index messages_sender_time on public.messages(sender_id,created_at desc);
create table public.device_tokens (
 token text primary key check(length(token) between 20 and 4096),
 user_id uuid not null references public.profiles on delete cascade,
 updated_at timestamptz not null default now()
);
create index device_tokens_owner on public.device_tokens(user_id);
create table public.notifications (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,
 room_id uuid not null references public.rooms on delete cascade,source_id uuid not null references public.messages on delete cascade,
 actor_id uuid not null references public.profiles on delete cascade,
 created_at timestamptz not null default now(),available_at timestamptz not null default now(),
 delivered_at timestamptz,locked_until timestamptz,attempts int not null default 0,
 unique(user_id,source_id)
);
create index notification_jobs on public.notifications(available_at) where delivered_at is null;

create function public.new_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.profiles(id,name) values(new.id,'Guest '||right(new.id::text,4));return new;end $$;
create trigger auth_profile after insert on auth.users for each row execute function public.new_profile();
create function public.active_user() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=auth.uid() and not p.suspended and (u.is_anonymous or u.email_confirmed_at is not null))
$$;
create function public.room_active(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.active_user() and exists(select 1 from public.rooms where id=rid and (is_lounge or expires_at>now()))
$$;
create function public.can_chat(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.room_active(rid) and exists(select 1 from public.room_members where room_id=rid and user_id=auth.uid())
$$;
create function public.enter_room(rid uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 -- Serialize with the cleanup worker. An already expired room cannot be joined.
 perform 1 from public.rooms where id=rid for share;
 if not public.room_active(rid) then raise exception 'This group has expired or is unavailable'; end if;
 if not exists(select 1 from public.room_members where room_id=rid and user_id=auth.uid()) and (select count(*) from public.room_members where room_id=rid)>=500 then raise exception 'This chat is full'; end if;
 insert into public.room_members(room_id,user_id) values(rid,auth.uid()) on conflict do nothing;
end $$;
create function public.create_room(p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid; started timestamptz=clock_timestamp();
begin
 if not public.active_user() then raise exception 'Please sign in'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1));
 if (select count(*) from public.rooms where owner_id=auth.uid() and expires_at>now())>=3 then raise exception 'You can have up to 3 active groups'; end if;
 insert into public.rooms(name,owner_id,created_at,expires_at) values(trim(p_name),auth.uid(),started,started+interval '1 hour') returning id into rid;
 insert into public.room_members(room_id,user_id) values(rid,auth.uid());
 return rid;
end $$;
create function public.guard_message() returns trigger language plpgsql set search_path='' as $$
begin
 new.sender_id=auth.uid();new.created_at=clock_timestamp();
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,2));
 if (select count(*) from public.messages where sender_id=auth.uid() and created_at>now()-interval '1 minute')>=20 then raise exception 'Please slow down and try again in a minute'; end if;
 return new;
end $$;
create trigger message_guard before insert on public.messages for each row execute function public.guard_message();
create function public.queue_push() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.notifications(user_id,room_id,source_id,actor_id)
 select m.user_id,new.room_id,new.id,new.sender_id from public.room_members m join public.profiles p on p.id=m.user_id
 where m.room_id=new.room_id and m.user_id<>new.sender_id and not m.muted and not p.suspended and p.push_enabled
 and exists(select 1 from public.device_tokens d where d.user_id=m.user_id and d.updated_at>now()-interval '30 days');
 return new;
end $$;
create trigger message_push after insert on public.messages for each row execute function public.queue_push();
create function public.register_device(p_token text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.active_user() then raise exception 'Please sign in'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,3));
 if (select count(*) from public.device_tokens where user_id=auth.uid())>=5 and not exists(select 1 from public.device_tokens where token=p_token and user_id=auth.uid()) then raise exception 'Device limit reached'; end if;
 insert into public.device_tokens(token,user_id) values(p_token,auth.uid()) on conflict(token) do update set updated_at=now() where public.device_tokens.user_id=auth.uid();
end $$;
create function public.unregister_device(p_token text) returns void language plpgsql security definer set search_path='' as $$
begin delete from public.device_tokens where token=p_token and user_id=auth.uid();end $$;
create function public.claim_push_jobs() returns setof public.notifications language sql security definer set search_path='' as $$
 update public.notifications set locked_until=now()+interval '2 minutes',attempts=attempts+1
 where id in (select id from public.notifications where delivered_at is null and available_at<=now() and attempts<5 and (locked_until is null or locked_until<now()) order by created_at for update skip locked limit 50) returning *
$$;
create function public.push_tokens(nid uuid) returns table(token text) language sql stable security definer set search_path='' as $$
 select d.token from public.notifications n join public.profiles p on p.id=n.user_id join auth.users u on u.id=p.id
 join public.room_members m on m.room_id=n.room_id and m.user_id=n.user_id join public.rooms r on r.id=m.room_id join public.device_tokens d on d.user_id=n.user_id
 where n.id=nid and p.push_enabled and not p.suspended and not m.muted and (u.is_anonymous or u.email_confirmed_at is not null)
 and (r.is_lounge or r.expires_at>now()) and d.updated_at>now()-interval '30 days'
$$;
create function public.server_time() returns timestamptz language sql stable set search_path='' as $$select now()$$;

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.messages enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(public.active_user());
create policy profiles_edit on public.profiles for update to authenticated using(id=auth.uid() and public.active_user()) with check(id=auth.uid());
create policy rooms_read on public.rooms for select to authenticated using(public.room_active(id));
create policy members_read on public.room_members for select to authenticated using(user_id=auth.uid() and public.room_active(room_id));
create policy members_edit on public.room_members for update to authenticated using(user_id=auth.uid() and public.can_chat(room_id)) with check(user_id=auth.uid());
create policy messages_read on public.messages for select to authenticated using(public.can_chat(room_id));
create policy messages_insert on public.messages for insert to authenticated with check(sender_id=auth.uid() and public.can_chat(room_id));
create policy messages_delete on public.messages for delete to authenticated using(sender_id=auth.uid() and public.can_chat(room_id));
create policy tokens_read on public.device_tokens for select to authenticated using(user_id=auth.uid() and public.active_user());
-- Notifications are a server-only outbox; no client policies or grants.
-- No client room deletion, expiry edits, sender edits or manual role assignment.
revoke all on public.profiles,public.rooms,public.room_members,public.messages,public.device_tokens,public.notifications from anon,authenticated;
grant select on public.profiles,public.rooms,public.room_members,public.messages,public.device_tokens to authenticated;
grant update(name,push_enabled) on public.profiles to authenticated;
grant update(muted) on public.room_members to authenticated;
grant insert(id,room_id,body),delete on public.messages to authenticated;
grant all on public.profiles,public.rooms,public.room_members,public.messages,public.device_tokens,public.notifications to service_role;
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.active_user(),public.room_active(uuid),public.can_chat(uuid),public.enter_room(uuid),public.create_room(text),public.register_device(text),public.unregister_device(text),public.server_time() to authenticated;
grant execute on function public.claim_push_jobs(),public.push_tokens(uuid) to service_role;
alter publication supabase_realtime add table public.messages;

-- Access stops at expires_at through RLS. Physical deletion follows within the
-- next cron minute, cascading to messages, memberships and pending pushes.
select cron.schedule('chitchat-cleanup','* * * * *', $job$
 delete from public.rooms where not is_lounge and expires_at<=now();
 delete from public.notifications where created_at<now()-interval '1 day';
 delete from public.device_tokens where updated_at<now()-interval '30 days';
$job$);
