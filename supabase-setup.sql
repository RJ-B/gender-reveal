-- Gender reveal anketa – nastavení databáze pro Supabase
-- Spusť celé v Supabase → SQL Editor → Run

-- 1) Tabulka hlasů
create table if not exists public.votes (
  id          bigint generated always as identity primary key,
  name        text not null check (char_length(name) between 1 and 60),
  choice      text not null check (choice in ('Kluk','Holka')),
  created_at  timestamptz not null default now()
);

-- 2) Zapnout Row Level Security
alter table public.votes enable row level security;

-- 3) Anon NESMÍ číst surová data (jména hlasujících) – jen přidat hlas.
--    Veřejná stránka čte pouze SOUHRNY přes funkci get_results() (viz níže),
--    kompletní data se jmény jen admin přes admin_data(pin).
create policy "verejne_vkladani"
  on public.votes for insert
  to anon
  with check (true);

-- ============================================================
-- 2. kolo: hlasování o oblíbenosti jména
-- ============================================================
create table if not exists public.name_votes (
  id          bigint generated always as identity primary key,
  category    text not null check (category in ('Kluk','Holka')),
  name        text not null check (char_length(name) between 1 and 60),
  voter       text,
  created_at  timestamptz not null default now()
);
alter table public.name_votes enable row level security;
-- anon smí jen vkládat (čtení jen přes souhrny / admin)
create policy "names_verejne_vkladani" on public.name_votes for insert to anon with check (true);

-- ============================================================
-- Skutečný výsledek (spoiler-proof) – vydá se až po čase odhalení
-- ============================================================
create table if not exists public.reveal (
  id        int primary key default 1,
  result    text check (result in ('Kluk','Holka')),
  reveal_at timestamptz not null default '2026-08-31 17:00:00+02',
  constraint reveal_single_row check (id = 1)
);
insert into public.reveal (id, result, reveal_at)
  values (1, null, '2026-08-31 17:00:00+02')
  on conflict (id) do nothing;

-- RLS bez anon práv = anon NEMŮŽE číst tabulku přímo (žádný spoiler přes API)
alter table public.reveal enable row level security;

-- Funkce vydá výsledek AŽ po čase odhalení (jinak 'locked' / 'not_set')
create or replace function public.get_reveal()
returns json
language sql
security definer
set search_path = public
as $$
  select case
    when now() < r.reveal_at then json_build_object('status','locked','reveal_at', r.reveal_at)
    when r.result is null     then json_build_object('status','not_set','reveal_at', r.reveal_at)
    else json_build_object('status','revealed','result', r.result,'reveal_at', r.reveal_at)
  end
  from public.reveal r where r.id = 1;
$$;
revoke all on function public.get_reveal() from public;
grant execute on function public.get_reveal() to anon;

-- Nastavení výsledku (spustí jen vlastník přes SQL editor / CLI):
--   update public.reveal set result = 'Holka' where id = 1;   -- nebo 'Kluk'

-- ============================================================
-- Veřejné SOUHRNY (bez jmen) pro grafy na stránce
-- ============================================================
create or replace function public.get_results()
returns json language sql security definer set search_path = public as $$
  select json_build_object(
    'boy',  (select count(*) from votes where choice='Kluk'),
    'girl', (select count(*) from votes where choice='Holka'),
    'boyNames',  (select coalesce(json_object_agg(name, c), '{}'::json)
                  from (select name, count(*) c from name_votes where category='Kluk' group by name) t),
    'girlNames', (select coalesce(json_object_agg(name, c), '{}'::json)
                  from (select name, count(*) c from name_votes where category='Holka' group by name) t)
  );
$$;
revoke all on function public.get_results() from public;
grant execute on function public.get_results() to anon;

-- ============================================================
-- ADMIN – PIN + rate limit; vrací kompletní data se jmény
-- ============================================================
create table if not exists public.admin_attempts (
  id bigint generated always as identity primary key,
  ok boolean not null,
  at timestamptz not null default now()
);
alter table public.admin_attempts enable row level security; -- žádná anon práva

create or replace function public.admin_data(pin text)
returns json language plpgsql security definer set search_path = public as $$
declare
  fails int;
  correct constant text := '71807180';   -- ZMĚNA PINU: uprav tady
begin
  -- rate limit: max 5 chybných pokusů za 60 sekund
  select count(*) into fails from admin_attempts
    where ok = false and at > now() - interval '60 seconds';
  if fails >= 5 then
    return json_build_object('status','rate_limited','retry_after',60);
  end if;

  if pin is distinct from correct then
    insert into admin_attempts(ok) values (false);
    return json_build_object('status','wrong','remaining', greatest(0, 5 - (fails+1)));
  end if;

  insert into admin_attempts(ok) values (true);
  return json_build_object(
    'status','ok',
    'gender', (select coalesce(json_agg(json_build_object('name',name,'choice',choice,'at',created_at) order by created_at desc), '[]'::json) from votes),
    'names',  (select coalesce(json_agg(json_build_object('voter',voter,'name',name,'category',category,'at',created_at) order by created_at desc), '[]'::json) from name_votes),
    'boy',  (select count(*) from votes where choice='Kluk'),
    'girl', (select count(*) from votes where choice='Holka'),
    'boyNames',  (select coalesce(json_object_agg(name, c), '{}'::json)
                  from (select name, count(*) c from name_votes where category='Kluk' group by name) t),
    'girlNames', (select coalesce(json_object_agg(name, c), '{}'::json)
                  from (select name, count(*) c from name_votes where category='Holka' group by name) t)
  );
end;
$$;
revoke all on function public.admin_data(text) from public;
grant execute on function public.admin_data(text) to anon;
