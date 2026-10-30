-- Run with psql as the local/staging database owner after migrations.
-- Transaction rolls back every fixture. Never run against production.
begin;
insert into auth.users(id,aud,role,is_anonymous,created_at,updated_at) values
 ('10000000-0000-4000-8000-000000000001','authenticated','authenticated',true,now(),now()),
 ('20000000-0000-4000-8000-000000000002','authenticated','authenticated',true,now(),now());
insert into public.rooms(id,name,owner_id,created_at,expires_at) values
 ('30000000-0000-4000-8000-000000000003','Active room','10000000-0000-4000-8000-000000000001',now(),now()+interval '1 hour'),
 ('40000000-0000-4000-8000-000000000004','Expired room','10000000-0000-4000-8000-000000000001',now()-interval '61 minutes',now()-interval '1 minute');
insert into public.room_members(room_id,user_id) values
 ('30000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001'),
 ('40000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
insert into public.messages(id,room_id,body) values
 ('50000000-0000-4000-8000-000000000005','30000000-0000-4000-8000-000000000003','Private until joined'),
 ('60000000-0000-4000-8000-000000000006','40000000-0000-4000-8000-000000000004','Expired message');
insert into public.device_tokens(token,user_id) values('private-test-device-fid-0001','10000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000002',true);
do $$
declare created uuid; touched int;
begin
 if (select count(*) from public.messages)<>0 then raise exception 'FAIL: unjoined user reads messages'; end if;
 if (select count(*) from public.device_tokens)<>0 then raise exception 'FAIL: device token leak'; end if;
 if exists(select 1 from public.rooms where id='40000000-0000-4000-8000-000000000004') then raise exception 'FAIL: expired room visible'; end if;
 begin
  insert into public.messages(id,room_id,body) values(gen_random_uuid(),'30000000-0000-4000-8000-000000000003','Unauthorized');
  raise exception 'FAIL: unjoined write accepted';
 exception when insufficient_privilege then null; end;
 begin
  update public.rooms set expires_at=now()+interval '5 hours';
  raise exception 'FAIL: client controls expiry';
 exception when insufficient_privilege then null; end;
 begin
  update public.profiles set suspended=false;
  raise exception 'FAIL: client controls suspension';
 exception when insufficient_privilege then null; end;
 begin
  perform public.claim_push_jobs();
  raise exception 'FAIL: client can dispatch arbitrary pushes';
 exception when insufficient_privilege then null; end;
 update public.profiles set name='Attacker' where id='10000000-0000-4000-8000-000000000001';
 get diagnostics touched=row_count;
 if touched<>0 then raise exception 'FAIL: another profile changed'; end if;
 perform public.enter_room('30000000-0000-4000-8000-000000000003');
 if (select count(*) from public.messages)<>1 then raise exception 'FAIL: joined user cannot read active chat'; end if;
 perform public.report_message('50000000-0000-4000-8000-000000000005','spam');
 if (select count(*) from public.reports)<>1 then raise exception 'FAIL: report was not stored'; end if;
 insert into public.user_blocks(blocked_id) values('10000000-0000-4000-8000-000000000001');
 if (select count(*) from public.messages)<>0 then raise exception 'FAIL: blocked messages remain visible'; end if;
 delete from public.user_blocks where blocked_id='10000000-0000-4000-8000-000000000001';
 if (select count(*) from public.messages)<>1 then raise exception 'FAIL: unblocking does not restore visibility'; end if;
 begin
  insert into public.messages(id,room_id,body,sender_id) values(gen_random_uuid(),'30000000-0000-4000-8000-000000000003','Spoof','10000000-0000-4000-8000-000000000001');
  raise exception 'FAIL: sender spoof column accepted';
 exception when insufficient_privilege then null; end;
 begin
  perform public.enter_room('40000000-0000-4000-8000-000000000004');
  raise exception 'FAIL: expired room can be joined';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
 created=public.create_room('Creator enters automatically');
 if not public.can_chat(created) then raise exception 'FAIL: creator is excluded from chat'; end if;
 if not exists(select 1 from public.rooms where id=created and expires_at=created_at+interval '1 hour') then raise exception 'FAIL: wrong expiry'; end if;
end $$;
reset role;
delete from public.rooms where not is_lounge and expires_at<=now();
do $$begin
 if exists(select 1 from public.messages where id='60000000-0000-4000-8000-000000000006') then raise exception 'FAIL: expired messages did not cascade'; end if;
 if exists(select 1 from pg_tables where schemaname='public' and tablename in ('profiles','rooms','room_members','messages','device_tokens','notifications') and not rowsecurity) then raise exception 'FAIL: exposed table lacks RLS'; end if;
end $$;
rollback;
