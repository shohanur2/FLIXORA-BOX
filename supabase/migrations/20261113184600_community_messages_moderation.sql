-- FLIXORA Community, direct messaging, reports and admin moderation.
create table if not exists public.community_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.community_user_moderation (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active','warned','muted','suspended','banned')),
  reason text,
  expires_at timestamptz,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 3000),
  movie_title text,
  created_at timestamptz not null default now(),
  removed_at timestamptz,
  removed_by uuid references auth.users(id) on delete set null
);

create table if not exists public.community_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 1200),
  created_at timestamptz not null default now(),
  removed_at timestamptz,
  removed_by uuid references auth.users(id) on delete set null
);

create table if not exists public.community_likes (
  post_id uuid not null references public.community_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.community_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('post','comment','user')),
  target_id uuid not null,
  reported_user_id uuid references auth.users(id) on delete set null,
  reason text not null check (char_length(trim(reason)) between 2 and 80),
  details text,
  status text not null default 'pending'
    check (status in ('pending','reviewed','actioned','dismissed')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz,
  primary key (conversation_id, user_id)
);

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists community_posts_created_at_idx on public.community_posts(created_at desc) where removed_at is null;
create index if not exists community_comments_post_created_idx on public.community_comments(post_id, created_at) where removed_at is null;
create index if not exists community_reports_status_created_idx on public.community_reports(status, created_at desc);
create index if not exists conversation_members_user_idx on public.conversation_members(user_id, joined_at desc);
create index if not exists direct_messages_conversation_created_idx on public.direct_messages(conversation_id, created_at desc);

create or replace function public.community_can_post()
returns boolean
language sql stable
set search_path = ''
as $$
  select coalesce((
    select m.status in ('active','warned') or (m.expires_at is not null and m.expires_at <= pg_catalog.now())
    from public.community_user_moderation m
    where m.user_id = (select auth.uid())
  ), true);
$$;

create or replace function public.community_can_message()
returns boolean
language sql stable
set search_path = ''
as $$
  select coalesce((
    select m.status in ('active','warned','muted') or (m.expires_at is not null and m.expires_at <= pg_catalog.now())
    from public.community_user_moderation m
    where m.user_id = (select auth.uid())
  ), true);
$$;

create or replace function public.is_community_conversation_member(p_conversation_id uuid)
returns boolean
language sql stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = p_conversation_id
      and cm.user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_community_conversation_member(uuid) from public, anon;
grant execute on function public.is_community_conversation_member(uuid) to authenticated;
grant execute on function public.community_can_post() to anon, authenticated;
grant execute on function public.community_can_message() to authenticated;

create or replace function public.start_direct_conversation(p_target_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_conversation_id uuid;
begin
  if v_me is null then
    raise exception 'Sign in to start a conversation.';
  end if;
  if p_target_user is null or p_target_user = v_me then
    raise exception 'Choose another FLIXORA user.';
  end if;
  if not exists (select 1 from public.community_profiles p where p.user_id = p_target_user) then
    raise exception 'This user is not available for messaging.';
  end if;
  if not public.community_can_message() then
    raise exception 'Your account is restricted from sending messages.';
  end if;
  if exists (
    select 1 from public.community_user_moderation m
    where m.user_id = p_target_user
      and m.status in ('suspended','banned')
      and (m.expires_at is null or m.expires_at > pg_catalog.now())
  ) then
    raise exception 'This user is not available for messaging.';
  end if;

  select c.id into v_conversation_id
  from public.conversations c
  where (select pg_catalog.count(*) from public.conversation_members cm where cm.conversation_id = c.id) = 2
    and exists (select 1 from public.conversation_members cm where cm.conversation_id = c.id and cm.user_id = v_me)
    and exists (select 1 from public.conversation_members cm where cm.conversation_id = c.id and cm.user_id = p_target_user)
  order by c.created_at desc
  limit 1;

  if v_conversation_id is not null then
    return v_conversation_id;
  end if;

  insert into public.conversations(created_by) values (v_me)
  returning id into v_conversation_id;

  insert into public.conversation_members(conversation_id, user_id)
  values (v_conversation_id, v_me), (v_conversation_id, p_target_user);

  return v_conversation_id;
end;
$$;

revoke all on function public.start_direct_conversation(uuid) from public, anon;
grant execute on function public.start_direct_conversation(uuid) to authenticated;

alter table public.community_profiles enable row level security;
alter table public.community_user_moderation enable row level security;
alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;
alter table public.community_likes enable row level security;
alter table public.community_reports enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.direct_messages enable row level security;

grant select on public.community_profiles to anon, authenticated;
grant insert, update on public.community_profiles to authenticated;
grant select on public.community_user_moderation to authenticated;
grant insert, update, delete on public.community_user_moderation to authenticated;
grant select, insert, update, delete on public.community_posts to authenticated;
grant select on public.community_posts to anon;
grant select, insert, delete on public.community_comments to authenticated;
grant select on public.community_comments to anon;
grant select, insert, delete on public.community_likes to authenticated;
grant select, insert, update on public.community_reports to authenticated;
grant select on public.conversations, public.conversation_members, public.direct_messages to authenticated;
grant update on public.conversation_members to authenticated;
grant insert on public.direct_messages to authenticated;

create policy "Community profiles are publicly readable" on public.community_profiles
for select to anon, authenticated using (true);
create policy "Users create own community profile" on public.community_profiles
for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Users update own community profile" on public.community_profiles
for update to authenticated using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users read own moderation status" on public.community_user_moderation
for select to authenticated using ((select auth.uid()) = user_id);
create policy "Admins read all moderation status" on public.community_user_moderation
for select to authenticated using (exists (select 1 from public.admins a where a.id = (select auth.uid())));
create policy "Admins insert moderation status" on public.community_user_moderation
for insert to authenticated with check (exists (select 1 from public.admins a where a.id = (select auth.uid())));
create policy "Admins update moderation status" on public.community_user_moderation
for update to authenticated using (exists (select 1 from public.admins a where a.id = (select auth.uid())))
with check (exists (select 1 from public.admins a where a.id = (select auth.uid())));
create policy "Admins delete moderation status" on public.community_user_moderation
for delete to authenticated using (exists (select 1 from public.admins a where a.id = (select auth.uid())));

create policy "Read visible community posts" on public.community_posts
for select to anon, authenticated using (removed_at is null);
create policy "Admins read removed community posts" on public.community_posts
for select to authenticated using (exists (select 1 from public.admins a where a.id = (select auth.uid())));
create policy "Signed in users publish posts" on public.community_posts
for insert to authenticated with check ((select auth.uid()) = author_id and (select public.community_can_post()));
create policy "Admins remove community posts" on public.community_posts
for update to authenticated using (exists (select 1 from public.admins a where a.id = (select auth.uid())))
with check (exists (select 1 from public.admins a where a.id = (select auth.uid())));

create policy "Read visible community comments" on public.community_comments
for select to anon, authenticated using (
  removed_at is null and exists (
    select 1 from public.community_posts p where p.id = post_id and p.removed_at is null
  )
);
create policy "Admins read all community comments" on public.community_comments
for select to authenticated using (exists (select 1 from public.admins a where a.id = (select auth.uid())));
create policy "Signed in users comment" on public.community_comments
for insert to authenticated with check (
  (select auth.uid()) = author_id and (select public.community_can_post())
  and exists (select 1 from public.community_posts p where p.id = post_id and p.removed_at is null)
);
create policy "Authors or admins remove comments" on public.community_comments
for delete to authenticated using (
  (select auth.uid()) = author_id
  or exists (select 1 from public.admins a where a.id = (select auth.uid()))
);

create policy "Read community likes" on public.community_likes
for select to anon, authenticated using (true);
create policy "Signed in users like posts" on public.community_likes
for insert to authenticated with check (
  (select auth.uid()) = user_id and (select public.community_can_post())
  and exists (select 1 from public.community_posts p where p.id = post_id and p.removed_at is null)
);
create policy "Users or admins remove likes" on public.community_likes
for delete to authenticated using (
  (select auth.uid()) = user_id
  or exists (select 1 from public.admins a where a.id = (select auth.uid()))
);

create policy "Users create own reports" on public.community_reports
for insert to authenticated with check ((select auth.uid()) = reporter_id);
create policy "Users read own reports" on public.community_reports
for select to authenticated using ((select auth.uid()) = reporter_id);
create policy "Admins read all reports" on public.community_reports
for select to authenticated using (exists (select 1 from public.admins a where a.id = (select auth.uid())));
create policy "Admins update reports" on public.community_reports
for update to authenticated using (exists (select 1 from public.admins a where a.id = (select auth.uid())))
with check (exists (select 1 from public.admins a where a.id = (select auth.uid())));

create policy "Conversation members read conversations" on public.conversations
for select to authenticated using (public.is_community_conversation_member(id));
create policy "Conversation members read memberships" on public.conversation_members
for select to authenticated using (public.is_community_conversation_member(conversation_id));
create policy "Users update own conversation read time" on public.conversation_members
for update to authenticated using (user_id = (select auth.uid()) and public.is_community_conversation_member(conversation_id))
with check (user_id = (select auth.uid()) and public.is_community_conversation_member(conversation_id));
create policy "Conversation members read direct messages" on public.direct_messages
for select to authenticated using (public.is_community_conversation_member(conversation_id));
create policy "Active conversation members send direct messages" on public.direct_messages
for insert to authenticated with check (
  sender_id = (select auth.uid())
  and public.is_community_conversation_member(conversation_id)
  and (select public.community_can_message())
);

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'community_posts') then
    alter publication supabase_realtime add table public.community_posts;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'community_comments') then
    alter publication supabase_realtime add table public.community_comments;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'direct_messages') then
    alter publication supabase_realtime add table public.direct_messages;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'community_user_moderation') then
    alter publication supabase_realtime add table public.community_user_moderation;
  end if;
end $$;
