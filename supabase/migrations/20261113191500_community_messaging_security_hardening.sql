-- Keep the conversation membership helper outside the exposed public API schema.
create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.is_community_conversation_member(p_conversation_id uuid)
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

revoke all on function private.is_community_conversation_member(uuid) from public, anon;
grant execute on function private.is_community_conversation_member(uuid) to authenticated;

drop policy if exists "Conversation members read conversations" on public.conversations;
create policy "Conversation members read conversations" on public.conversations
for select to authenticated using (private.is_community_conversation_member(id));

drop policy if exists "Conversation members read memberships" on public.conversation_members;
create policy "Conversation members read memberships" on public.conversation_members
for select to authenticated using (private.is_community_conversation_member(conversation_id));

drop policy if exists "Users update own conversation read time" on public.conversation_members;
create policy "Users update own conversation read time" on public.conversation_members
for update to authenticated
using (user_id = (select auth.uid()) and private.is_community_conversation_member(conversation_id))
with check (user_id = (select auth.uid()) and private.is_community_conversation_member(conversation_id));

drop policy if exists "Conversation members read direct messages" on public.direct_messages;
create policy "Conversation members read direct messages" on public.direct_messages
for select to authenticated using (private.is_community_conversation_member(conversation_id));

drop policy if exists "Active conversation members send direct messages" on public.direct_messages;
create policy "Active conversation members send direct messages" on public.direct_messages
for insert to authenticated with check (
  sender_id = (select auth.uid())
  and private.is_community_conversation_member(conversation_id)
  and (select public.community_can_message())
  and not exists (
    select 1
    from public.conversation_members cm
    join public.community_user_moderation m on m.user_id = cm.user_id
    where cm.conversation_id = direct_messages.conversation_id
      and m.status in ('suspended','banned')
      and (m.expires_at is null or m.expires_at > pg_catalog.now())
  )
);

drop function if exists public.is_community_conversation_member(uuid);
