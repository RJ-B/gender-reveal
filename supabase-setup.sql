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
