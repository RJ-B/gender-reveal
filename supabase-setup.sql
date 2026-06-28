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

-- 3) Kdokoli (anon) smí číst výsledky
create policy "verejne_cteni"
  on public.votes for select
  to anon
  using (true);

-- 4) Kdokoli (anon) smí přidat svůj hlas (ne mazat/měnit)
create policy "verejne_vkladani"
  on public.votes for insert
  to anon
  with check (true);

-- 5) Zapnout realtime (živé výsledky)
alter publication supabase_realtime add table public.votes;

-- ============================================================
-- 2. kolo: hlasování o oblíbenosti jména
-- ============================================================
create table if not exists public.name_votes (
  id          bigint generated always as identity primary key,
  category    text not null check (category in ('Kluk','Holka')),
  name        text not null check (char_length(name) between 1 and 60),
  created_at  timestamptz not null default now()
);
alter table public.name_votes enable row level security;
create policy "names_verejne_cteni"    on public.name_votes for select to anon using (true);
create policy "names_verejne_vkladani" on public.name_votes for insert to anon with check (true);
alter publication supabase_realtime add table public.name_votes;

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
