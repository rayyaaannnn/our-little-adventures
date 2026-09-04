-- Run this ONCE in Supabase SQL Editor.
-- This creates a shared couple space. Both accounts join using the same couple code.

create table if not exists couples (
  id uuid primary key default gen_random_uuid(),
  join_code text unique not null,
  created_at timestamptz not null default now()
);

create table if not exists couple_members (
  couple_id uuid references couples(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  primary key (couple_id,user_id)
);

alter table bucket_items add column if not exists couple_id uuid references couples(id) on delete cascade;
alter table bucket_items add column if not exists user_id uuid references auth.users(id) on delete cascade;

alter table couples enable row level security;
alter table couple_members enable row level security;
alter table bucket_items enable row level security;

drop policy if exists "Users can view their own items" on bucket_items;
drop policy if exists "Users can add their own items" on bucket_items;
drop policy if exists "Users can update their own items" on bucket_items;
drop policy if exists "Users can delete their own items" on bucket_items;

create policy "Members can view shared items" on bucket_items for select to authenticated
using (exists (select 1 from couple_members m where m.couple_id=bucket_items.couple_id and m.user_id=auth.uid()));

create policy "Members can add shared items" on bucket_items for insert to authenticated
with check (exists (select 1 from couple_members m where m.couple_id=bucket_items.couple_id and m.user_id=auth.uid()));

create policy "Members can update shared items" on bucket_items for update to authenticated
using (exists (select 1 from couple_members m where m.couple_id=bucket_items.couple_id and m.user_id=auth.uid()))
with check (exists (select 1 from couple_members m where m.couple_id=bucket_items.couple_id and m.user_id=auth.uid()));

create policy "Members can delete shared items" on bucket_items for delete to authenticated
using (exists (select 1 from couple_members m where m.couple_id=bucket_items.couple_id and m.user_id=auth.uid()));

-- Helper RPC: creates a couple and adds the logged-in user.
create or replace function create_couple(code text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare cid uuid;
begin
  if length(trim(code)) < 4 then raise exception 'Code must be at least 4 characters'; end if;
  insert into couples(join_code) values (trim(code)) returning id into cid;
  insert into couple_members(couple_id,user_id) values (cid,auth.uid());
  return cid;
end $$;

-- Helper RPC: joins an existing couple using its code.
create or replace function join_couple(code text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare cid uuid;
begin
  select id into cid from couples where join_code=trim(code);
  if cid is null then raise exception 'Couple code not found'; end if;
  insert into couple_members(couple_id,user_id) values (cid,auth.uid()) on conflict do nothing;
  return cid;
end $$;

grant execute on function create_couple(text) to authenticated;
grant execute on function join_couple(text) to authenticated;

-- SECURITY NOTE:
-- The supplied website currently demonstrates login/database connectivity.
-- For the shared version, after creating accounts, use the couple RPCs and
-- add couple_id to inserted bucket_items. The UI can be upgraded to expose
-- the couple-code onboarding screen.
