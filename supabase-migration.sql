-- Run this after registering the legacy data owner's email in Supabase Auth.
-- Replace YOUR_REGISTERED_EMAIL with that exact account email before running.
-- This migration assigns existing shared rows to that one account, then locks
-- user data down so authenticated users can only access their own rows.

create extension if not exists pgcrypto;

create table if not exists public.trading_journal (
  id uuid primary key default gen_random_uuid(),
  trade_date date not null,
  pair text not null,
  direction text not null,
  lot numeric not null,
  entry_price numeric,
  sl_pips numeric,
  tp_pips numeric,
  result_pips numeric,
  result_usc numeric not null,
  status text not null,
  notes text,
  created_at timestamptz default now()
);

create table if not exists public.sop_checklist (
  id text primary key,
  is_checked boolean not null default false,
  updated_at timestamptz default now()
);

create table if not exists public.trading_account_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  total_deposit_usc numeric not null check (total_deposit_usc > 0),
  initial_balance_usc numeric not null check (initial_balance_usc >= 0),
  usd_idr_rate numeric not null check (usd_idr_rate > 0),
  cent_units_per_lot numeric not null check (cent_units_per_lot > 0),
  risk_percent numeric not null check (risk_percent > 0 and risk_percent <= 3),
  pip_value_usc_per_lot numeric not null check (pip_value_usc_per_lot > 0),
  leverage numeric not null check (leverage > 0),
  stop_out_level_percent numeric not null check (stop_out_level_percent > 0 and stop_out_level_percent <= 100),
  sl_min_pips numeric not null check (sl_min_pips > 0),
  sl_max_pips numeric not null check (sl_max_pips >= sl_min_pips),
  tp_min_pips numeric not null check (tp_min_pips > 0),
  tp_max_pips numeric not null check (tp_max_pips >= tp_min_pips),
  minimum_reward_risk_ratio numeric not null check (minimum_reward_risk_ratio >= 1.5),
  max_trades_per_day integer not null check (max_trades_per_day > 0 and max_trades_per_day <= 2),
  daily_loss_limit_usc numeric not null check (daily_loss_limit_usc > 0),
  max_drawdown_percent numeric not null check (max_drawdown_percent > 0 and max_drawdown_percent <= 100),
  be_trigger_min_pips numeric not null check (be_trigger_min_pips > 0),
  be_trigger_max_pips numeric not null check (be_trigger_max_pips >= be_trigger_min_pips),
  be_lock_pips numeric not null check (be_lock_pips >= 0),
  trading_days_per_month integer not null check (trading_days_per_month > 0),
  growth_plan jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.account_cashflows (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  flow_date date not null,
  flow_type text not null check (flow_type in ('deposit', 'withdrawal')),
  amount_usc numeric not null check (amount_usc > 0),
  notes text,
  created_at timestamptz not null default now()
);

alter table public.trading_journal
  add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.sop_checklist
  add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.trading_journal
  add column if not exists result_pips numeric;

do $$
declare
  legacy_owner_id uuid;
begin
  select id
    into legacy_owner_id
    from auth.users
   where lower(email) = lower('YOUR_REGISTERED_EMAIL');

  if legacy_owner_id is null then
    raise exception 'No Supabase Auth account found for YOUR_REGISTERED_EMAIL. Replace the placeholder and run again.';
  end if;

  update public.trading_journal
     set user_id = legacy_owner_id
   where user_id is null;

  update public.sop_checklist
     set user_id = legacy_owner_id
   where user_id is null;
end;
$$;

alter table public.trading_journal
  alter column user_id set not null;
alter table public.sop_checklist
  alter column user_id set not null;

alter table public.sop_checklist
  drop constraint if exists sop_checklist_pkey;
alter table public.sop_checklist
  add constraint sop_checklist_pkey primary key (user_id, id);

create index if not exists trading_journal_user_trade_date_idx
  on public.trading_journal (user_id, trade_date desc, created_at desc);

alter table public.trading_journal enable row level security;
alter table public.sop_checklist enable row level security;
alter table public.trading_account_settings enable row level security;
alter table public.account_cashflows enable row level security;

drop policy if exists "Public Access trading_journal" on public.trading_journal;
drop policy if exists "Public Access sop_checklist" on public.sop_checklist;

drop policy if exists "Users read own trading journal" on public.trading_journal;
drop policy if exists "Users insert own trading journal" on public.trading_journal;
drop policy if exists "Users update own trading journal" on public.trading_journal;
drop policy if exists "Users delete own trading journal" on public.trading_journal;
create policy "Users read own trading journal"
  on public.trading_journal for select to authenticated
  using (auth.uid() = user_id);
create policy "Users insert own trading journal"
  on public.trading_journal for insert to authenticated
  with check (auth.uid() = user_id);
create policy "Users update own trading journal"
  on public.trading_journal for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "Users delete own trading journal"
  on public.trading_journal for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users read own SOP checklist" on public.sop_checklist;
drop policy if exists "Users insert own SOP checklist" on public.sop_checklist;
drop policy if exists "Users update own SOP checklist" on public.sop_checklist;
drop policy if exists "Users delete own SOP checklist" on public.sop_checklist;
create policy "Users read own SOP checklist"
  on public.sop_checklist for select to authenticated
  using (auth.uid() = user_id);
create policy "Users insert own SOP checklist"
  on public.sop_checklist for insert to authenticated
  with check (auth.uid() = user_id);
create policy "Users update own SOP checklist"
  on public.sop_checklist for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "Users delete own SOP checklist"
  on public.sop_checklist for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users manage own account settings" on public.trading_account_settings;
create policy "Users manage own account settings"
  on public.trading_account_settings for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users manage own account cashflows" on public.account_cashflows;
create policy "Users manage own account cashflows"
  on public.account_cashflows for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on public.trading_journal from anon;
revoke all on public.sop_checklist from anon;
revoke all on public.trading_account_settings from anon;
revoke all on public.account_cashflows from anon;
grant select, insert, update, delete on public.trading_journal to authenticated;
grant select, insert, update, delete on public.sop_checklist to authenticated;
grant select, insert, update, delete on public.trading_account_settings to authenticated;
grant select, insert, update, delete on public.account_cashflows to authenticated;
