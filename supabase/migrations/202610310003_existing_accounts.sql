-- Include identities created before the application schema was deployed.
insert into public.profiles(id,name)
select id,'Guest '||right(id::text,4) from auth.users
on conflict(id) do nothing;
