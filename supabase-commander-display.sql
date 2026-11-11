begin;

create table if not exists public.commander_displays (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  viewer_id uuid references auth.users(id) on delete set null,
  title text not null check (char_length(title) between 1 and 80),
  cards jsonb not null
);

alter table public.commander_displays enable row level security;
revoke all on public.commander_displays from public, anon, authenticated;

create or replace function public.commander_display_settings(p_workspace uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.workspace_members m
    where m.workspace_id = p_workspace and m.user_id = auth.uid() and m.role in ('owner', 'admin')
  ) then
    raise exception 'Access denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'settings', (select to_jsonb(d) - 'workspace_id' from public.commander_displays d where d.workspace_id = p_workspace),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object('id', u.id, 'email', u.email) order by u.email)
      from auth.users u
      where u.email is not null and exists (
        select 1 from public.workspace_members m where m.workspace_id = p_workspace and m.user_id = u.id
      )
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.commander_display_save(p_workspace uuid, p_viewer uuid, p_title text, p_cards jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.workspace_members m
    where m.workspace_id = p_workspace and m.user_id = auth.uid() and m.role in ('owner', 'admin')
  ) then
    raise exception 'Access denied' using errcode = '42501';
  end if;
  if p_viewer is not null and not exists (
    select 1 from public.workspace_members m where m.workspace_id = p_workspace and m.user_id = p_viewer
  ) then
    raise exception 'Viewer must be a workspace member' using errcode = '22023';
  end if;
  if p_cards is null or jsonb_typeof(p_cards) <> 'array' or char_length(p_cards::text) > 10000 then
    raise exception 'Invalid cards' using errcode = '22023';
  end if;
  if jsonb_array_length(p_cards) > 8 or exists (
    select 1 from jsonb_array_elements(p_cards) as c
    where jsonb_typeof(c) <> 'object'
       or jsonb_typeof(c->'title') is distinct from 'string'
       or jsonb_typeof(c->'text') is distinct from 'string'
       or jsonb_typeof(c->'visible') is distinct from 'boolean'
       or char_length(btrim(c->>'title')) not between 1 and 80
       or char_length(btrim(c->>'text')) not between 1 and 600
  ) then
    raise exception 'Invalid cards' using errcode = '22023';
  end if;
  insert into public.commander_displays (workspace_id, viewer_id, title, cards)
    values (p_workspace, p_viewer, btrim(p_title), p_cards)
    on conflict (workspace_id) do update
    set viewer_id = excluded.viewer_id, title = excluded.title, cards = excluded.cards;
end;
$$;

create or replace function public.commander_display_view(p_workspace uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('title', d.title, 'cards', coalesce((
    select jsonb_agg(jsonb_build_object('title', c->>'title', 'text', c->>'text') order by n)
    from jsonb_array_elements(d.cards) with ordinality as cards(c,n)
    where c->'visible' = 'true'::jsonb
  ), '[]'::jsonb))
  from public.commander_displays d
  where d.workspace_id = p_workspace and d.viewer_id = auth.uid()
    and exists (
      select 1 from public.workspace_members m where m.workspace_id = p_workspace and m.user_id = auth.uid()
    );
$$;

revoke all on function public.commander_display_settings(uuid) from public, anon, authenticated;
revoke all on function public.commander_display_save(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.commander_display_view(uuid) from public, anon, authenticated;
grant execute on function public.commander_display_settings(uuid) to authenticated;
grant execute on function public.commander_display_save(uuid, uuid, text, jsonb) to authenticated;
grant execute on function public.commander_display_view(uuid) to authenticated;

commit;
