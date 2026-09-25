-- تشغيل مرة واحدة في Supabase SQL Editor
create table if not exists public.public_pages (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  slug text not null,
  title text not null,
  content jsonb not null default '{}'::jsonb,
  published boolean not null default false,
  updated_at timestamptz not null default now(),
  unique(workspace_id, slug),
  unique(slug)
);

alter table public.public_pages enable row level security;
grant select on public.public_pages to anon, authenticated;
grant insert, update, delete on public.public_pages to authenticated;

drop policy if exists "public can view published pages" on public.public_pages;
create policy "public can view published pages" on public.public_pages
for select to anon, authenticated using (
  published = true or exists (
    select 1 from public.workspace_members m
    where m.workspace_id = public_pages.workspace_id and m.user_id = auth.uid()
  )
);

drop policy if exists "workspace admins manage public pages" on public.public_pages;
create policy "workspace admins manage public pages" on public.public_pages
for all to authenticated using (
  exists (
    select 1 from public.workspace_members m
    where m.workspace_id = public_pages.workspace_id and m.user_id = auth.uid() and m.role = 'admin'
  )
) with check (
  exists (
    select 1 from public.workspace_members m
    where m.workspace_id = public_pages.workspace_id and m.user_id = auth.uid() and m.role = 'admin'
  )
);
