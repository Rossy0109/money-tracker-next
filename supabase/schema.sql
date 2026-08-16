create extension if not exists pgcrypto;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 email text not null,
 display_name text,
 currency text not null default 'BDT',
 locale text not null default 'bn-BD',
 role text not null default 'ACCOUNTANT' check (role in ('ADMIN','ACCOUNTANT','VIEWER')),
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.accounts (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 name text not null, type text not null default 'cash', currency text not null default 'BDT',
 opening_balance numeric(18,2) not null default 0, balance numeric(18,2) not null default 0,
 institution text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.categories (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 name text not null, type text not null check(type in('income','expense')), icon text default '📁',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(user_id,name,type)
);

create table if not exists public.transactions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 amount numeric(18,2) not null check(amount >= 0), date date not null, type text not null check(type in('income','expense')),
 category_name text not null, category_id uuid references public.categories(id) on delete set null,
 description text not null default '', method text not null default 'Cash', account_id uuid references public.accounts(id) on delete set null,
 currency text not null default 'BDT', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.budgets (id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,amount numeric(18,2) not null default 0,category_name text not null,month_year text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.projects (id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,name text not null,budget numeric(18,2) not null default 0,status text not null default 'active',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.debts (id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,name text not null,balance numeric(18,2) not null default 0,opening_balance numeric(18,2) not null default 0,apr numeric(8,4) not null default 0,min_payment numeric(18,2) not null default 0,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.financial_goals (id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,name text not null,target_amount numeric(18,2) not null default 0,current_amount numeric(18,2) not null default 0,is_completed boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.bill_reminders (id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,title text not null,amount numeric(18,2) not null default 0,due_date date not null,repeat_monthly boolean not null default false,is_paid boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.recurring_transactions (id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,name text not null,amount numeric(18,2) not null default 0,type text not null default 'expense' check(type in('income','expense')),frequency text not null default 'monthly',category_name text,next_date date,is_active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now());

create or replace function public.set_updated_at() returns trigger language plpgsql set search_path=public as $$ begin new.updated_at=now(); return new; end $$;
create or replace function public.recalculate_account_balance(p_account_id uuid) returns void language plpgsql security invoker set search_path=public as $$ begin update public.accounts a set balance=a.opening_balance+coalesce((select sum(case when t.type='income' then t.amount else -t.amount end) from public.transactions t where t.account_id=a.id and t.user_id=a.user_id),0),updated_at=now() where a.id=p_account_id; end $$;
create or replace function public.sync_account_balance() returns trigger language plpgsql set search_path=public as $$ begin if tg_op='DELETE' then if old.account_id is not null then perform public.recalculate_account_balance(old.account_id); end if; return old; end if; if tg_op='UPDATE' and old.account_id is distinct from new.account_id and old.account_id is not null then perform public.recalculate_account_balance(old.account_id); end if; if new.account_id is not null then perform public.recalculate_account_balance(new.account_id); end if; return new; end $$;
drop trigger if exists transactions_sync_account on public.transactions;
create trigger transactions_sync_account after insert or update or delete on public.transactions for each row execute function public.sync_account_balance();

do $$ declare t text; begin foreach t in array array['profiles','accounts','categories','transactions','budgets','projects','debts','financial_goals','bill_reminders','recurring_transactions'] loop execute format('drop trigger if exists updated_at_trigger on public.%I',t); execute format('create trigger updated_at_trigger before update on public.%I for each row execute function public.set_updated_at()',t); end loop; end $$;

create index if not exists idx_transactions_user_date on public.transactions(user_id,date desc);
create index if not exists idx_transactions_account on public.transactions(account_id);
create index if not exists idx_transactions_category on public.transactions(category_id);
create index if not exists idx_accounts_user on public.accounts(user_id);
create index if not exists idx_categories_user on public.categories(user_id);
create index if not exists idx_projects_user on public.projects(user_id);
create index if not exists idx_debts_user on public.debts(user_id);
create index if not exists idx_recurring_user_next on public.recurring_transactions(user_id,next_date);

alter table public.profiles enable row level security; alter table public.accounts enable row level security; alter table public.categories enable row level security; alter table public.transactions enable row level security; alter table public.budgets enable row level security; alter table public.projects enable row level security; alter table public.debts enable row level security; alter table public.financial_goals enable row level security; alter table public.bill_reminders enable row level security; alter table public.recurring_transactions enable row level security;

do $$ declare t text; begin foreach t in array array['profiles','accounts','categories','transactions','budgets','projects','debts','financial_goals','bill_reminders','recurring_transactions'] loop execute format('drop policy if exists owner_all on public.%I',t); execute format('create policy owner_all on public.%I for all to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id)',t); end loop; end $$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles(id,email) values(new.id,new.email) on conflict(id) do update set email=excluded.email; return new; end $$;
revoke all on function public.handle_new_user() from public,anon,authenticated;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Default categories are created per user by the application after first sign-in.
