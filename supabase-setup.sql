create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  username text,
  role text not null default 'user' check (role in ('user', 'read_only', 'admin', 'developer')),
  created_at timestamptz not null default now()
);

alter table public.profiles add column if not exists username text;

update public.profiles as p
set username = left(
  coalesce(
    nullif(trim(both '_' from regexp_replace(lower(split_part(u.email, '@', 1)), '[^a-z0-9_]', '_', 'g')), ''),
    'user'
  ),
  15
) || '_' || substr(replace(p.user_id::text, '-', ''), 1, 8)
from auth.users as u
where u.id = p.user_id
  and p.username is null;

alter table public.profiles alter column username set not null;
create unique index if not exists profiles_username_lower_idx on public.profiles (lower(username));

create table if not exists public.papertrade_portfolios (
  user_id uuid primary key references auth.users (id) on delete cascade,
  cash numeric(18, 2) not null default 10000 check (cash >= 0),
  closed_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.papertrade_positions (
  user_id uuid not null references auth.users (id) on delete cascade,
  ticker text not null,
  quantity numeric(24, 8) not null check (quantity > 0),
  average_price numeric(24, 8) not null check (average_price > 0),
  primary key (user_id, ticker)
);

create table if not exists public.papertrade_trades (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  ticker text not null,
  action text not null check (action in ('buy', 'sell', 'reset', 'closed', 'reopened')),
  quantity numeric(24, 8) not null default 0,
  price numeric(24, 8) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.papertrade_transfers (
  id bigint generated always as identity primary key,
  sender_id uuid not null references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  amount numeric(18, 2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);

create table if not exists public.papertrade_account_access (
  user_id uuid primary key references auth.users (id) on delete cascade,
  last_ip text,
  last_ip_at timestamptz
);

create table if not exists public.papertrade_server_control (
  id smallint primary key default 1 check (id = 1),
  price_multiplier numeric(8, 6) not null default 1 check (price_multiplier > 0 and price_multiplier <= 1),
  announcement text,
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.papertrade_server_control (id) values (1)
on conflict (id) do nothing;

create table if not exists public.papertrade_world_players (
  user_id uuid primary key references auth.users (id) on delete cascade,
  x integer not null default 800 check (x between 0 and 1600),
  y integer not null default 450 check (y between 0 and 900),
  mining_block_id bigint,
  last_seen_at timestamptz not null default now()
);

create table if not exists public.papertrade_world_blocks (
  id bigint generated always as identity primary key,
  reward numeric(18, 2) not null check (reward in (5000, 25000, 100000, 1000000, 5000000, 30000000)),
  x integer not null check (x between 80 and 1520),
  y integer not null check (y between 80 and 820),
  remaining_seconds numeric(10, 2) not null check (remaining_seconds between 0 and 1800),
  last_progress_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.papertrade_world_players
  drop constraint if exists papertrade_world_players_mining_block_id_fkey;
alter table public.papertrade_world_players
  add constraint papertrade_world_players_mining_block_id_fkey
  foreign key (mining_block_id) references public.papertrade_world_blocks (id) on delete set null;

create table if not exists public.papertrade_world_contributors (
  block_id bigint not null references public.papertrade_world_blocks (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  contributed_seconds numeric(12, 2) not null default 0 check (contributed_seconds >= 0),
  primary key (block_id, user_id)
);

create table if not exists public.papertrade_world_spawn_control (
  id smallint primary key default 1 check (id = 1),
  next_spawn_at timestamptz not null default now()
);

insert into public.papertrade_world_spawn_control (id) values (1)
on conflict (id) do nothing;

create table if not exists public.papertrade_world_chat (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null,
  message text not null check (length(message) between 1 and 240),
  created_at timestamptz not null default now()
);

create index if not exists papertrade_world_players_seen_idx
  on public.papertrade_world_players (last_seen_at desc);
create index if not exists papertrade_world_blocks_progress_idx
  on public.papertrade_world_blocks (last_progress_at);
create index if not exists papertrade_world_chat_created_idx
  on public.papertrade_world_chat (created_at desc);

create index if not exists papertrade_trades_user_created_idx
  on public.papertrade_trades (user_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.papertrade_portfolios enable row level security;
alter table public.papertrade_positions enable row level security;
alter table public.papertrade_trades enable row level security;
alter table public.papertrade_transfers enable row level security;
alter table public.papertrade_account_access enable row level security;
alter table public.papertrade_server_control enable row level security;
alter table public.papertrade_world_players enable row level security;
alter table public.papertrade_world_blocks enable row level security;
alter table public.papertrade_world_contributors enable row level security;
alter table public.papertrade_world_spawn_control enable row level security;
alter table public.papertrade_world_chat enable row level security;

create or replace function public.papertrade_current_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles as p
  where p.user_id = (select auth.uid())
$$;

revoke all on function public.papertrade_current_role() from public, anon;
grant execute on function public.papertrade_current_role() to authenticated;

drop policy if exists "Read own profile or developer profiles" on public.profiles;
create policy "Read own profile or developer profiles"
  on public.profiles for select to authenticated
  using (user_id = (select auth.uid()) or (select public.papertrade_current_role()) = 'developer');

drop policy if exists "Read own portfolio or developer portfolios" on public.papertrade_portfolios;
create policy "Read own portfolio or developer portfolios"
  on public.papertrade_portfolios for select to authenticated
  using (user_id = (select auth.uid()) or (select public.papertrade_current_role()) = 'developer');

drop policy if exists "Read own positions or developer positions" on public.papertrade_positions;
create policy "Read own positions or developer positions"
  on public.papertrade_positions for select to authenticated
  using (user_id = (select auth.uid()) or (select public.papertrade_current_role()) = 'developer');

drop policy if exists "Read own trades or developer trades" on public.papertrade_trades;
create policy "Read own trades or developer trades"
  on public.papertrade_trades for select to authenticated
  using (user_id = (select auth.uid()) or (select public.papertrade_current_role()) = 'developer');

revoke all on table public.profiles, public.papertrade_portfolios, public.papertrade_positions, public.papertrade_trades, public.papertrade_transfers, public.papertrade_account_access, public.papertrade_server_control, public.papertrade_world_players, public.papertrade_world_blocks, public.papertrade_world_contributors, public.papertrade_world_spawn_control, public.papertrade_world_chat from anon, authenticated;
grant select on table public.profiles, public.papertrade_portfolios, public.papertrade_positions, public.papertrade_trades to authenticated;
grant select on table public.profiles to service_role;
grant select, insert, update on table public.papertrade_account_access to service_role;

create or replace function public.papertrade_create_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, username, role)
  values (
    new.id,
    case
      when coalesce(new.raw_user_meta_data ->> 'username', '') ~ '^[A-Za-z0-9_]{3,24}$'
        then lower(new.raw_user_meta_data ->> 'username')
      else 'user_' || substr(replace(new.id::text, '-', ''), 1, 12)
    end,
    'user'
  )
  on conflict (user_id) do nothing;

  insert into public.papertrade_portfolios (user_id, cash)
  values (new.id, 10000)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists papertrade_create_account on auth.users;
create trigger papertrade_create_account
  after insert on auth.users
  for each row execute function public.papertrade_create_account();

create or replace function public.papertrade_trade(
  p_ticker text,
  p_action text,
  p_quantity numeric,
  p_price numeric
)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_cash numeric(18, 2);
  v_closed_at timestamptz;
  v_quantity numeric(24, 8);
  v_average numeric(24, 8);
  v_new_quantity numeric(24, 8);
  v_cost numeric(18, 2);
begin
  if v_user_id is null then
    raise exception 'Bitte melde dich an, um zu handeln.';
  end if;
  if coalesce((select public.papertrade_current_role()), '') not in ('user', 'admin', 'developer') then
    raise exception 'Dein Konto hat nur Leserechte.';
  end if;
  if p_ticker is null or length(p_ticker) < 1 or length(p_ticker) > 20
     or p_action not in ('buy', 'sell')
     or p_quantity is null or p_quantity <= 0 or p_quantity > 1000000000
     or p_price is null or p_price <= 0 or p_price > 1000000000000 then
    raise exception 'Ungültige Handelsdaten.';
  end if;

  p_quantity := round(p_quantity, 8);
  v_cost := round(p_quantity * p_price, 2);

  select p.cash, p.closed_at
    into v_cash, v_closed_at
    from public.papertrade_portfolios as p
    where p.user_id = v_user_id
    for update;
  if not found then
    raise exception 'Für dieses Konto wurde kein Depot gefunden.';
  end if;
  if v_closed_at is not null then
    raise exception 'Dieses virtuelle Depot wurde geschlossen. Bitte wende dich an einen Developer.';
  end if;

  select p.quantity, p.average_price
    into v_quantity, v_average
    from public.papertrade_positions as p
    where p.user_id = v_user_id and p.ticker = p_ticker
    for update;
  if not found then
    v_quantity := 0;
    v_average := 0;
  end if;

  if p_action = 'buy' then
    if v_cost > v_cash then
      raise exception 'Dafür reicht dein virtuelles Guthaben nicht aus.';
    end if;
    v_new_quantity := v_quantity + p_quantity;
    insert into public.papertrade_positions (user_id, ticker, quantity, average_price)
    values (v_user_id, p_ticker, v_new_quantity, (v_quantity * v_average + v_cost) / v_new_quantity)
    on conflict (user_id, ticker) do update
      set quantity = excluded.quantity, average_price = excluded.average_price;
    update public.papertrade_portfolios
      set cash = v_cash - v_cost, updated_at = now()
      where user_id = v_user_id;
  else
    if p_quantity > v_quantity then
      raise exception 'Du hast nicht genügend Anteile zum Verkaufen.';
    end if;
    v_new_quantity := round(v_quantity - p_quantity, 8);
    if v_new_quantity <= 0.00000001 then
      delete from public.papertrade_positions
        where user_id = v_user_id and ticker = p_ticker;
    else
      update public.papertrade_positions
        set quantity = v_new_quantity
        where user_id = v_user_id and ticker = p_ticker;
    end if;
    update public.papertrade_portfolios
      set cash = v_cash + v_cost, updated_at = now()
      where user_id = v_user_id;
  end if;

  insert into public.papertrade_trades (user_id, ticker, action, quantity, price)
  values (v_user_id, p_ticker, p_action, p_quantity, p_price);

  return case when p_action = 'buy' then v_cash - v_cost else v_cash + v_cost end;
end;
$$;

drop function if exists public.papertrade_admin_list_users();
create function public.papertrade_admin_list_users()
returns table (user_id uuid, username text, email text, role text, created_at timestamptz, last_ip text, last_ip_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce((select public.papertrade_current_role()), '') not in ('admin', 'developer') then
    raise exception 'Keine Berechtigung für die Kontenverwaltung.';
  end if;

  return query
    select u.id, p.username,
           case when u.email like '%@accounts.papertrade.invalid' then null else u.email::text end,
           p.role, p.created_at, access.last_ip, access.last_ip_at
    from auth.users as u
    join public.profiles as p on p.user_id = u.id
    left join public.papertrade_account_access as access on access.user_id = u.id
    order by p.username;
end;
$$;

create or replace function public.papertrade_server_state()
returns table (price_multiplier numeric, announcement text, updated_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select control.price_multiplier, control.announcement, control.updated_at
  from public.papertrade_server_control as control
  where control.id = 1
$$;

create or replace function public.papertrade_developer_set_server_control(
  p_price_multiplier numeric,
  p_announcement text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce((select public.papertrade_current_role()), '') <> 'developer' then
    raise exception 'Nur Developer dürfen die Serversteuerung ändern.';
  end if;
  if p_price_multiplier is null or p_price_multiplier < 0.0001 or p_price_multiplier > 1 then
    raise exception 'Der Kursfaktor muss zwischen 0,01 %% und 100 %% liegen.';
  end if;
  if p_announcement is not null and length(trim(p_announcement)) > 500 then
    raise exception 'Die Servernachricht darf höchstens 500 Zeichen enthalten.';
  end if;

  update public.papertrade_server_control
    set price_multiplier = p_price_multiplier,
        announcement = nullif(trim(p_announcement), ''),
        updated_by = auth.uid(),
        updated_at = now()
    where id = 1;
end;
$$;

create or replace function public.papertrade_developer_adjust_cash(
  p_username text,
  p_operation text,
  p_amount numeric
)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_cash numeric(18, 2);
  v_closed_at timestamptz;
  v_new_cash numeric(18, 2);
begin
  if coalesce((select public.papertrade_current_role()), '') <> 'developer' then
    raise exception 'Nur Developer dürfen Guthaben ändern.';
  end if;
  if p_username is null or length(trim(p_username)) < 3 or length(trim(p_username)) > 24
     or trim(p_username) !~ '^[A-Za-z0-9_]+$'
     or p_operation is null or p_operation not in ('set', 'add')
     or p_amount is null or p_amount < 0 or p_amount > 1000000000
     or p_amount <> round(p_amount, 2) then
    raise exception 'Ungültiger Spieler oder Geldbetrag.';
  end if;

  select profile.user_id into v_user_id
    from public.profiles as profile
    where lower(profile.username) = lower(trim(p_username));
  if not found then
    raise exception 'Spieler nicht gefunden.';
  end if;

  select portfolio.cash, portfolio.closed_at
    into v_cash, v_closed_at
    from public.papertrade_portfolios as portfolio
    where portfolio.user_id = v_user_id
    for update;
  if not found or v_closed_at is not null then
    raise exception 'Das Depot ist geschlossen oder nicht verfügbar.';
  end if;

  v_new_cash := case when p_operation = 'set' then p_amount else v_cash + p_amount end;
  if v_new_cash > 1000000000 then
    raise exception 'Das Guthaben darf 1.000.000.000 € nicht überschreiten.';
  end if;
  update public.papertrade_portfolios
    set cash = v_new_cash, updated_at = now()
    where user_id = v_user_id;
  return v_new_cash;
end;
$$;
create or replace function public.papertrade_admin_set_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_role text := (select public.papertrade_current_role());
  v_existing_role text;
begin
  if coalesce(v_actor_role, '') not in ('admin', 'developer') then
    raise exception 'Keine Berechtigung, Rollen zu ändern.';
  end if;
  if p_role not in ('user', 'read_only', 'admin', 'developer') then
    raise exception 'Unbekannte Rolle.';
  end if;
  if v_actor_role = 'admin' and p_role = 'developer' then
    raise exception 'Nur ein Developer darf die Developer-Rolle vergeben.';
  end if;

  select p.role into v_existing_role
    from public.profiles as p
    where p.user_id = p_user_id
    for update;
  if not found then
    raise exception 'Konto nicht gefunden.';
  end if;
  if v_actor_role = 'admin' and v_existing_role = 'developer' then
    raise exception 'Admins dürfen die Developer-Rolle nicht ändern.';
  end if;
  if p_user_id = auth.uid() and p_role <> v_existing_role then
    raise exception 'Du kannst deine eigene Rolle nicht ändern.';
  end if;
  if v_existing_role = 'developer' and p_role <> 'developer'
     and (select count(*) from public.profiles where role = 'developer') <= 1 then
    raise exception 'Der letzte Developer kann nicht herabgestuft werden.';
  end if;

  update public.profiles set role = p_role where user_id = p_user_id;
end;
$$;

drop function if exists public.papertrade_developer_list_portfolios();
create function public.papertrade_developer_list_portfolios()
returns table (
  user_id uuid,
  username text,
  role text,
  cash numeric,
  closed_at timestamptz,
  ticker text,
  quantity numeric,
  average_price numeric
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce((select public.papertrade_current_role()), '') <> 'developer' then
    raise exception 'Nur Developer dürfen Depots einsehen.';
  end if;

  return query
    select p.user_id, pr.username, pr.role, p.cash, p.closed_at,
           pos.ticker, pos.quantity, pos.average_price
    from public.papertrade_portfolios as p
    join public.profiles as pr on pr.user_id = p.user_id
    left join public.papertrade_positions as pos on pos.user_id = p.user_id
    order by p.updated_at desc, pr.username, pos.ticker;
end;
$$;

create or replace function public.papertrade_list_players()
returns table (
  user_id uuid,
  username text,
  cash numeric,
  closed_at timestamptz,
  ticker text,
  quantity numeric,
  average_price numeric
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Bitte melde dich an, um die Spielerliste anzusehen.';
  end if;

  return query
    select portfolio.user_id, profile.username, portfolio.cash, portfolio.closed_at,
           position.ticker, position.quantity, position.average_price
    from public.papertrade_portfolios as portfolio
    join public.profiles as profile on profile.user_id = portfolio.user_id
    left join public.papertrade_positions as position on position.user_id = portfolio.user_id
    order by profile.username, position.ticker;
end;
$$;

create or replace function public.papertrade_transfer_money(p_username text, p_amount numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sender_id uuid := auth.uid();
  v_sender_role text := (select public.papertrade_current_role());
  v_recipient_id uuid;
  v_locked_user_id uuid;
  v_sender_cash numeric(18, 2);
  v_recipient_cash numeric(18, 2);
  v_sender_closed_at timestamptz;
  v_recipient_closed_at timestamptz;
begin
  if v_sender_id is null then
    raise exception 'Bitte melde dich an, um virtuelles Geld zu überweisen.';
  end if;
  if v_sender_role is null or v_sender_role = 'read_only' then
    raise exception 'Dieses Konto darf kein virtuelles Geld überweisen.';
  end if;
  if p_username is null or length(trim(p_username)) < 3 or length(trim(p_username)) > 24
     or trim(p_username) !~ '^[A-Za-z0-9_]+$'
     or p_amount is null or p_amount <= 0 or p_amount > 1000000000
     or p_amount <> round(p_amount, 2) then
    raise exception 'Bitte gib einen gültigen Spielernamen und einen Betrag in Euro-Cent ein.';
  end if;

  select profile.user_id into v_recipient_id
    from public.profiles as profile
    where lower(profile.username) = lower(trim(p_username));
  if not found then
    raise exception 'Dieser Spieler wurde nicht gefunden.';
  end if;
  if v_recipient_id = v_sender_id then
    raise exception 'Du kannst dir selbst kein Geld überweisen.';
  end if;

  for v_locked_user_id in
    select portfolio.user_id
      from public.papertrade_portfolios as portfolio
      where portfolio.user_id in (v_sender_id, v_recipient_id)
      order by portfolio.user_id
  loop
    perform 1
      from public.papertrade_portfolios as portfolio
      where portfolio.user_id = v_locked_user_id
      for update;
  end loop;

  select portfolio.cash, portfolio.closed_at
    into v_sender_cash, v_sender_closed_at
    from public.papertrade_portfolios as portfolio
    where portfolio.user_id = v_sender_id;
  if not found or v_sender_closed_at is not null then
    raise exception 'Dein virtuelles Depot ist geschlossen oder nicht verfügbar.';
  end if;

  select portfolio.cash, portfolio.closed_at
    into v_recipient_cash, v_recipient_closed_at
    from public.papertrade_portfolios as portfolio
    where portfolio.user_id = v_recipient_id;
  if not found or v_recipient_closed_at is not null then
    raise exception 'Das virtuelle Depot dieses Spielers ist geschlossen oder nicht verfügbar.';
  end if;
  if p_amount > v_sender_cash then
    raise exception 'Dafür reicht dein verfügbares virtuelles Guthaben nicht aus.';
  end if;

  update public.papertrade_portfolios
    set cash = v_sender_cash - p_amount, updated_at = now()
    where user_id = v_sender_id;
  update public.papertrade_portfolios
    set cash = v_recipient_cash + p_amount, updated_at = now()
    where user_id = v_recipient_id;
  insert into public.papertrade_transfers (sender_id, recipient_id, amount)
  values (v_sender_id, v_recipient_id, p_amount);
end;
$$;

drop function if exists public.papertrade_developer_list_trades();
create function public.papertrade_developer_list_trades()
returns table (
  trade_id bigint,
  username text,
  ticker text,
  action text,
  quantity numeric,
  price numeric,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce((select public.papertrade_current_role()), '') <> 'developer' then
    raise exception 'Nur Developer dürfen Handelshistorien einsehen.';
  end if;

  return query
    select t.id, p.username, t.ticker, t.action, t.quantity, t.price, t.created_at
    from public.papertrade_trades as t
    join public.profiles as p on p.user_id = t.user_id
    order by t.created_at desc
    limit 100;
end;
$$;

create or replace function public.papertrade_developer_close_portfolio(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_closed_at timestamptz;
begin
  if coalesce((select public.papertrade_current_role()), '') <> 'developer' then
    raise exception 'Nur Developer dürfen Depots schließen.';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Du kannst dein eigenes Depot nicht schließen.';
  end if;

  select p.closed_at into v_closed_at
    from public.papertrade_portfolios as p
    where p.user_id = p_user_id
    for update;
  if not found or v_closed_at is not null then
    raise exception 'Das Depot ist nicht geöffnet oder wurde nicht gefunden.';
  end if;

  delete from public.papertrade_positions where user_id = p_user_id;
  update public.papertrade_portfolios
    set cash = 0, closed_at = now(), updated_at = now()
    where user_id = p_user_id;
  insert into public.papertrade_trades (user_id, ticker, action)
  values (p_user_id, 'PORTFOLIO', 'closed');
end;
$$;

create or replace function public.papertrade_developer_reopen_portfolio(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_closed_at timestamptz;
begin
  if coalesce((select public.papertrade_current_role()), '') <> 'developer' then
    raise exception 'Nur Developer dürfen Depots wieder eröffnen.';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Dein eigenes Depot kann nicht hierüber wieder geöffnet werden.';
  end if;

  select p.closed_at into v_closed_at
    from public.papertrade_portfolios as p
    where p.user_id = p_user_id
    for update;
  if not found or v_closed_at is null then
    raise exception 'Das Depot ist nicht geschlossen oder wurde nicht gefunden.';
  end if;

  update public.papertrade_portfolios
    set cash = 10000, closed_at = null, updated_at = now()
    where user_id = p_user_id;
  insert into public.papertrade_trades (user_id, ticker, action)
  values (p_user_id, 'PORTFOLIO', 'reopened');
end;
$$;

create or replace function public.papertrade_world_sync(
  p_x integer,
  p_y integer,
  p_mine_block_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_role text := coalesce((select public.papertrade_current_role()), '');
  v_old_x integer;
  v_old_y integer;
  v_old_mining bigint;
  v_last_seen timestamptz;
  v_block public.papertrade_world_blocks%rowtype;
  v_spawn public.papertrade_world_spawn_control%rowtype;
  v_reward numeric(18, 2);
  v_roll numeric;
  v_active_miners integer;
  v_recipient_count integer;
  v_base_share numeric(18, 2);
  v_remainder_cents integer;
  v_contributor record;
  v_elapsed numeric;
  v_index integer;
  v_cash numeric(18, 2);
  v_closed_at timestamptz;
  v_block_count integer;
begin
  if v_user_id is null then
    raise exception 'Bitte melde dich an, um die Welt zu betreten.';
  end if;
  perform pg_advisory_xact_lock(684311200);
  if v_role = '' then
    raise exception 'Dieses Konto darf die Multiplayer-Welt nicht betreten.';
  end if;
  if (p_x is null) <> (p_y is null)
     or (p_x is not null and (p_x not between 0 and 1600 or p_y not between 0 and 900)) then
    raise exception 'Ungültige Weltposition.';
  end if;
  if p_mine_block_id is not null and p_x is null then
    raise exception 'Synchronisiere zuerst deine Weltposition, bevor du mit dem Abbau beginnst.';
  end if;

  select portfolio.cash, portfolio.closed_at
    into v_cash, v_closed_at
    from public.papertrade_portfolios as portfolio
    where portfolio.user_id = v_user_id;
  if not found or v_closed_at is not null then
    raise exception 'Für dieses Konto ist kein aktives Depot verfügbar.';
  end if;

  select player.x, player.y, player.mining_block_id, player.last_seen_at
    into v_old_x, v_old_y, v_old_mining, v_last_seen
    from public.papertrade_world_players as player
    where player.user_id = v_user_id
    for update;

  if not found then
    v_old_x := 800;
    v_old_y := 450;
    v_old_mining := null;
    v_last_seen := v_now;
    insert into public.papertrade_world_players (user_id, x, y, last_seen_at)
    values (v_user_id, v_old_x, v_old_y, v_now);
  end if;

  if v_old_mining is not null then
    if exists (select 1 from public.papertrade_world_blocks where id = v_old_mining) then
      if (p_mine_block_id is not null and p_mine_block_id <> v_old_mining)
         or (p_x is not null and (p_x <> v_old_x or p_y <> v_old_y)) then
        raise exception 'Du kannst dich während des Abbaus nicht bewegen.';
      end if;
    else
      v_old_mining := null;
      update public.papertrade_world_players set mining_block_id = null where user_id = v_user_id;
    end if;
  end if;

  if v_old_mining is null and p_mine_block_id is not null then
    select block.x, block.y into v_block.x, v_block.y
      from public.papertrade_world_blocks as block
      where block.id = p_mine_block_id;
    if not found then
      p_mine_block_id := null;
    else
      if (p_x - v_block.x) ^ 2 + (p_y - v_block.y) ^ 2 > 90 ^ 2 then
        raise exception 'Stelle dich näher an den Geldblock.';
      end if;
      update public.papertrade_world_blocks set last_progress_at = v_now where id = p_mine_block_id;
      insert into public.papertrade_world_contributors (block_id, user_id)
      values (p_mine_block_id, v_user_id)
      on conflict (block_id, user_id) do nothing;
      v_old_mining := p_mine_block_id;
    end if;
  end if;

  if v_old_mining is null and p_x is not null then
    v_elapsed := least(30, greatest(0.1, extract(epoch from v_now - v_last_seen)));
    if sqrt((p_x - v_old_x)::numeric ^ 2 + (p_y - v_old_y)::numeric ^ 2) > v_elapsed * 220 + 45 then
      raise exception 'Die Bewegung war zu schnell. Bitte versuche es erneut.';
    end if;
  end if;

  update public.papertrade_world_players
    set x = case when v_old_mining is null and p_x is not null then p_x else v_old_x end,
        y = case when v_old_mining is null and p_y is not null then p_y else v_old_y end,
        mining_block_id = v_old_mining,
        last_seen_at = v_now
    where user_id = v_user_id;

  for v_block in
    select block.*
      from public.papertrade_world_blocks as block
      order by block.id
      for update
  loop
    select count(*) into v_active_miners
      from public.papertrade_world_players as player
      where player.mining_block_id = v_block.id
        and player.last_seen_at >= v_now - interval '20 seconds';
    v_elapsed := greatest(0, extract(epoch from v_now - v_block.last_progress_at));

    if v_active_miners > 0 and v_elapsed > 0 then
      update public.papertrade_world_contributors as contributor
        set contributed_seconds = contributor.contributed_seconds + v_elapsed
        where contributor.block_id = v_block.id
          and contributor.user_id in (
            select player.user_id
            from public.papertrade_world_players as player
            where player.mining_block_id = v_block.id
              and player.last_seen_at >= v_now - interval '20 seconds'
          );
    end if;

    v_block.remaining_seconds := greatest(0, v_block.remaining_seconds - v_elapsed * v_active_miners);
    update public.papertrade_world_blocks
      set remaining_seconds = v_block.remaining_seconds, last_progress_at = v_now
      where id = v_block.id;

    if v_block.remaining_seconds <= 0 then
      select count(*) into v_recipient_count
        from public.papertrade_world_contributors as contributor
        join public.papertrade_portfolios as portfolio on portfolio.user_id = contributor.user_id
        where contributor.block_id = v_block.id
          and contributor.contributed_seconds > 0
          and portfolio.closed_at is null;
      if v_recipient_count > 0 then
        v_base_share := trunc(v_block.reward * 100 / v_recipient_count) / 100;
        v_remainder_cents := (v_block.reward * 100 - v_base_share * 100 * v_recipient_count)::integer;
        v_index := 0;
        for v_contributor in
          select contributor.user_id
            from public.papertrade_world_contributors as contributor
            join public.papertrade_portfolios as portfolio on portfolio.user_id = contributor.user_id
            where contributor.block_id = v_block.id
              and contributor.contributed_seconds > 0
              and portfolio.closed_at is null
            order by contributor.joined_at, contributor.user_id
        loop
          v_index := v_index + 1;
          update public.papertrade_portfolios
            set cash = cash + v_base_share + case when v_index <= v_remainder_cents then 0.01 else 0 end,
                updated_at = v_now
            where user_id = v_contributor.user_id;
        end loop;
      end if;
      update public.papertrade_world_players set mining_block_id = null where mining_block_id = v_block.id;
      delete from public.papertrade_world_blocks where id = v_block.id;
    end if;
  end loop;

  delete from public.papertrade_world_players
    where last_seen_at < v_now - interval '2 minutes';
  delete from public.papertrade_world_chat
    where created_at < v_now - interval '1 day';

  select * into v_spawn
    from public.papertrade_world_spawn_control
    where id = 1
    for update;
  select count(*) into v_block_count from public.papertrade_world_blocks;
  if v_spawn.next_spawn_at <= v_now then
    if v_block_count < 5 then
      v_roll := random();
      v_reward := case
        when v_roll < 0.70 then 5000
        when v_roll < 0.90 then 25000
        when v_roll < 0.97 then 100000
        when v_roll < 0.99 then 1000000
        when v_roll < 0.999 then 5000000
        else 30000000
      end;
      insert into public.papertrade_world_blocks (reward, x, y, remaining_seconds)
      values (v_reward, 100 + floor(random() * 1401)::integer, 100 + floor(random() * 701)::integer,
              60 + floor(random() * 1741)::integer);
      update public.papertrade_world_spawn_control
        set next_spawn_at = v_now + make_interval(secs => 60 + floor(random() * 1741)::integer)
        where id = 1;
    else
      update public.papertrade_world_spawn_control set next_spawn_at = v_now + interval '1 minute' where id = 1;
    end if;
  end if;

  select portfolio.cash into v_cash
    from public.papertrade_portfolios as portfolio
    where portfolio.user_id = v_user_id;

  return jsonb_build_object(
    'cash', v_cash,
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', player.user_id,
        'username', profile.username,
        'x', player.x,
        'y', player.y,
        'mining_block_id', player.mining_block_id
      ) order by profile.username)
      from public.papertrade_world_players as player
      join public.profiles as profile on profile.user_id = player.user_id
      where player.last_seen_at >= v_now - interval '20 seconds'
    ), '[]'::jsonb),
    'blocks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', block.id,
        'reward', block.reward,
        'x', block.x,
        'y', block.y,
        'remaining_seconds', block.remaining_seconds
      ) order by block.id)
      from public.papertrade_world_blocks as block
    ), '[]'::jsonb),
    'chat', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', recent.id,
        'username', recent.username,
        'message', recent.message,
        'created_at', recent.created_at
      ) order by recent.id)
      from (
        select message.id, message.username, message.message, message.created_at
          from public.papertrade_world_chat as message
          order by message.id desc
          limit 40
      ) as recent
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.papertrade_world_send_chat(p_message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_username text;
  v_message text := trim(coalesce(p_message, ''));
  v_last_username text;
begin
  if v_user_id is null then
    raise exception 'Bitte melde dich an, um im Welt-Chat zu schreiben.';
  end if;
  if length(v_message) < 1 or length(v_message) > 240 then
    raise exception 'Chatnachrichten müssen zwischen 1 und 240 Zeichen lang sein.';
  end if;
  select profile.username into v_last_username
    from public.profiles as profile
    where profile.user_id = v_user_id
    for update;
  if v_last_username is null then
    raise exception 'Für dieses Konto wurde kein Spielername gefunden.';
  end if;
  if exists (
    select 1 from public.papertrade_world_chat as recent
    where recent.user_id = v_user_id
      and recent.created_at > clock_timestamp() - interval '1 second'
  ) then
    raise exception 'Bitte warte kurz, bevor du die nächste Nachricht sendest.';
  end if;
  v_username := v_last_username;
  insert into public.papertrade_world_chat (user_id, username, message)
  values (v_user_id, v_username, v_message);
end;
$$;

create or replace function public.papertrade_world_leave()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Bitte melde dich zuerst an.';
  end if;
  delete from public.papertrade_world_players where user_id = auth.uid();
end;
$$;

create or replace function public.papertrade_developer_spawn_block(p_reward numeric default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reward numeric(18, 2);
  v_roll numeric;
  v_block public.papertrade_world_blocks%rowtype;
begin
  if coalesce((select public.papertrade_current_role()), '') <> 'developer' then
    raise exception 'Nur Developer dürfen Geldblöcke spawnen.';
  end if;
  perform pg_advisory_xact_lock(684311200);
  if p_reward is not null and p_reward not in (5000, 25000, 100000, 1000000, 5000000, 30000000) then
    raise exception 'Wähle eine gültige Blockstufe: 5000, 25000, 100000, 1000000, 5000000 oder 30000000.';
  end if;
  if (select count(*) from public.papertrade_world_blocks) >= 5 then
    raise exception 'Es sind bereits fünf Geldblöcke in der Welt.';
  end if;
  if p_reward is null then
    v_roll := random();
    v_reward := case
      when v_roll < 0.70 then 5000
      when v_roll < 0.90 then 25000
      when v_roll < 0.97 then 100000
      when v_roll < 0.99 then 1000000
      when v_roll < 0.999 then 5000000
      else 30000000
    end;
  else
    v_reward := p_reward;
  end if;
  insert into public.papertrade_world_blocks (reward, x, y, remaining_seconds)
  values (v_reward, 100 + floor(random() * 1401)::integer, 100 + floor(random() * 701)::integer,
          60 + floor(random() * 1741)::integer)
  returning * into v_block;
  return jsonb_build_object(
    'id', v_block.id,
    'reward', v_block.reward,
    'x', v_block.x,
    'y', v_block.y,
    'remaining_seconds', v_block.remaining_seconds
  );
end;
$$;

revoke all on function public.papertrade_trade(text, text, numeric, numeric) from public, anon;
drop function if exists public.papertrade_reset_portfolio();
revoke all on function public.papertrade_admin_list_users() from public, anon;
revoke all on function public.papertrade_admin_set_role(uuid, text) from public, anon;
revoke all on function public.papertrade_developer_list_portfolios() from public, anon;
revoke all on function public.papertrade_list_players() from public, anon;
revoke all on function public.papertrade_transfer_money(text, numeric) from public, anon;
revoke all on function public.papertrade_developer_list_trades() from public, anon;
revoke all on function public.papertrade_developer_close_portfolio(uuid) from public, anon;
revoke all on function public.papertrade_developer_reopen_portfolio(uuid) from public, anon;
revoke all on function public.papertrade_server_state() from public, anon;
revoke all on function public.papertrade_developer_set_server_control(numeric, text) from public, anon;
revoke all on function public.papertrade_developer_adjust_cash(text, text, numeric) from public, anon;
revoke all on function public.papertrade_world_sync(integer, integer, bigint) from public, anon;
revoke all on function public.papertrade_world_send_chat(text) from public, anon;
revoke all on function public.papertrade_world_leave() from public, anon;
revoke all on function public.papertrade_developer_spawn_block(numeric) from public, anon;

grant execute on function public.papertrade_trade(text, text, numeric, numeric) to authenticated;
grant execute on function public.papertrade_admin_list_users() to authenticated;
grant execute on function public.papertrade_admin_set_role(uuid, text) to authenticated;
grant execute on function public.papertrade_developer_list_portfolios() to authenticated;
grant execute on function public.papertrade_list_players() to authenticated;
grant execute on function public.papertrade_transfer_money(text, numeric) to authenticated;
grant execute on function public.papertrade_developer_list_trades() to authenticated;
grant execute on function public.papertrade_developer_close_portfolio(uuid) to authenticated;
grant execute on function public.papertrade_developer_reopen_portfolio(uuid) to authenticated;
grant execute on function public.papertrade_server_state() to anon, authenticated;
grant execute on function public.papertrade_developer_set_server_control(numeric, text) to authenticated;
grant execute on function public.papertrade_developer_adjust_cash(text, text, numeric) to authenticated;
grant execute on function public.papertrade_world_sync(integer, integer, bigint) to authenticated;
grant execute on function public.papertrade_world_send_chat(text) to authenticated;
grant execute on function public.papertrade_world_leave() to authenticated;
grant execute on function public.papertrade_developer_spawn_block(numeric) to authenticated;
