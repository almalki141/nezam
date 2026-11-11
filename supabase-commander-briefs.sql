begin;

create or replace function public.commander_display_save_layout(
  p_workspace uuid, p_viewer uuid, p_title text, p_cards jsonb, p_layout jsonb
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.commander_display_save(p_workspace, p_viewer, p_title, p_cards);
  if jsonb_typeof(p_layout->'pages') is distinct from 'array'
     or jsonb_typeof(p_layout->'updates') is distinct from 'boolean' then
    raise exception 'Invalid display layout' using errcode = '22023';
  end if;
  if jsonb_array_length(p_layout->'pages') > 100 or exists (
    select 1 from jsonb_array_elements(p_layout->'pages') as items(item)
    where jsonb_typeof(item) <> 'object'
       or (coalesce(item->>'key','') not in ('announcements','guide','templates','transactions')
           and coalesce(item->>'key','') !~ '^(transactions|page):[A-Za-z0-9_-]{1,80}$')
       or case when item->>'key' like 'page:%'
               then coalesce(item->>'mode','') not in ('link','brief')
               else coalesce(item->>'mode','') not in ('summary','full')
          end
       or (item ? 'brief' and (jsonb_typeof(item->'brief') is distinct from 'string'
                               or char_length(item->>'brief') > 400))
  ) then
    raise exception 'Invalid display pages' using errcode = '22023';
  end if;
  update public.commander_displays as d
  set layout = jsonb_build_object(
    'updates', p_layout->'updates',
    'pages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', item->>'key',
        'mode', case when item->>'mode' = 'link' then 'brief' else item->>'mode' end,
        'brief', coalesce(btrim(item->>'brief'), (
          select previous->>'brief'
          from jsonb_array_elements(d.layout->'pages') as old_items(previous)
          where previous->>'key' = item->>'key'
          limit 1
        ), '')
      ) order by position)
      from jsonb_array_elements(p_layout->'pages') with ordinality as items(item,position)
    ), '[]'::jsonb)
  )
  where d.workspace_id = p_workspace;
end;
$$;

commit;
