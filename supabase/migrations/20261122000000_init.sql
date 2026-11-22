-- Kuro initial schema.
--
-- Design notes (see docs/ARCHITECTURE.md):
-- * Clients never read or write `messages` directly. They call security-definer
--   RPCs so rate limits, bans and filtering cannot be bypassed, and so the real
--   author of an anonymous message is never sent to other clients.
-- * New messages are pushed to `room:<bundle id>` private Realtime channels by
--   `send_message` via realtime.send with a sanitized payload.
-- * History is short-lived like livestream danmaku: join shows the last 50
--   messages from the last 10 minutes; rows are purged after 24 hours.

create extension if not exists citext;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Secrets (server-only)
-- ---------------------------------------------------------------------------

create table private.secrets (
  name  text primary key,
  value text not null
);

-- Used to derive per-room, per-day anonymous author keys. Rotate to unlink history.
insert into private.secrets (name, value)
values ('author_key_secret', encode(extensions.gen_random_bytes(32), 'hex'));

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  username          citext not null unique
                    check (username ~ '^[A-Za-z0-9_一-鿿]{2,20}$'),
  display_name      text not null check (char_length(display_name) between 1 and 24),
  avatar_url        text check (avatar_url is null or avatar_url ~ '^https://'),
  bio               text not null default '' check (char_length(bio) <= 80),
  accent_color      text not null default '#FF5A5F' check (accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  default_anonymous boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table public.reserved_usernames (
  username citext primary key
);
insert into public.reserved_usernames (username) values
  ('admin'), ('kuro'), ('official'), ('support'), ('moderator'), ('system'), ('匿名'), ('官方'), ('管理员');

create table public.messages (
  id            uuid primary key default gen_random_uuid(),
  room          text not null check (room ~ '^[A-Za-z0-9.\-]{3,155}$'),
  user_id       uuid not null references auth.users (id) on delete cascade,
  body          text not null check (char_length(body) between 1 and 80),
  is_anonymous  boolean not null,
  display_name  text not null,          -- snapshot: profile name or anonymous alias
  avatar_url    text,                   -- snapshot; null when anonymous
  author_key    text not null,          -- hmac(user, room, day): lets clients filter blocks
  hidden        boolean not null default false,
  created_at    timestamptz not null default now()
);
create index messages_room_recent on public.messages (room, created_at desc);
create index messages_user_recent on public.messages (user_id, created_at desc);

create table public.blocks (
  id         uuid primary key default gen_random_uuid(),
  blocker    uuid not null references auth.users (id) on delete cascade,
  blocked    uuid not null references auth.users (id) on delete cascade,
  label      text not null,             -- what the blocker saw, e.g. "匿名 · 橘猫"
  created_at timestamptz not null default now(),
  unique (blocker, blocked),
  check (blocker <> blocked)
);

create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  message_id  uuid not null references public.messages (id) on delete cascade,
  reporter    uuid not null references auth.users (id) on delete cascade,
  reason      text not null check (reason in ('spam', 'abuse', 'sexual', 'hate', 'privacy', 'other')),
  created_at  timestamptz not null default now(),
  unique (message_id, reporter)
);

create table public.bans (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  reason     text not null,
  until      timestamptz,                -- null = permanent
  created_at timestamptz not null default now()
);

create table public.banned_terms (
  term citext primary key
);

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles           enable row level security;
alter table public.reserved_usernames enable row level security;
alter table public.messages           enable row level security;
alter table public.blocks             enable row level security;
alter table public.reports            enable row level security;
alter table public.bans               enable row level security;
alter table public.banned_terms       enable row level security;

-- Profiles are public account cards (no app / room information lives here).
create policy "profiles are readable by signed-in users"
  on public.profiles for select to authenticated using (true);
create policy "users insert their own profile"
  on public.profiles for insert to authenticated
  with check (id = auth.uid()
              and not exists (select 1 from public.reserved_usernames r where r.username = profiles.username));
create policy "users update their own profile"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid()
              and not exists (select 1 from public.reserved_usernames r where r.username = profiles.username));

-- messages, blocks, reports, bans, banned_terms: no client policies.
-- All access goes through the functions below.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function private.author_key(p_user uuid, p_room text)
returns text
language sql stable security definer set search_path = ''
as $$
  select left(encode(extensions.hmac(
           p_user::text || ':' || p_room || ':' || (now() at time zone 'utc')::date::text,
           (select value from private.secrets where name = 'author_key_secret'),
           'sha256'), 'hex'), 20);
$$;

-- Stable-for-the-day alias like "匿名 · 橘猫·3f2".
create function private.anon_name(p_key text)
returns text
language sql immutable set search_path = ''
as $$
  select '匿名 · ' ||
         (array['橘猫','柴犬','水獭','企鹅','狐狸','熊猫','海豹','仓鼠','考拉','树懒',
                '刺猬','浣熊','鲸鱼','章鱼','鹦鹉','羊驼'])
           [1 + (('x' || substr(p_key, 1, 4))::bit(16)::int % 16)]
         || '·' || substr(p_key, 18, 3);
$$;

create function private.is_banned(p_user uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.bans b
                 where b.user_id = p_user and (b.until is null or b.until > now()));
$$;

create function private.message_payload(m public.messages)
returns jsonb
language sql stable set search_path = ''
as $$
  select jsonb_build_object(
    'id', m.id,
    'room', m.room,
    'body', m.body,
    'is_anonymous', m.is_anonymous,
    'display_name', m.display_name,
    'avatar_url', m.avatar_url,
    'author_id', case when m.is_anonymous then null else m.user_id end,
    'author_key', m.author_key,
    'created_at', m.created_at
  );
$$;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

create function public.send_message(p_room text, p_body text, p_anonymous boolean)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_body    text := btrim(regexp_replace(coalesce(p_body, ''), '\s+', ' ', 'g'));
  v_profile public.profiles;
  v_created timestamptz;
  v_key     text;
  v_last    public.messages;
  v_count   int;
  v_msg     public.messages;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_room !~ '^[A-Za-z0-9.\-]{3,155}$' then raise exception 'invalid_room' using errcode = '22023'; end if;
  if char_length(v_body) = 0 or char_length(v_body) > 80 then
    raise exception 'invalid_body' using errcode = '22023';
  end if;
  if private.is_banned(v_uid) then raise exception 'banned' using errcode = '42501'; end if;

  select created_at into v_created from auth.users where id = v_uid;
  if v_created > now() - interval '10 minutes' then
    raise exception 'account_too_new' using errcode = '42501';
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  if not found then raise exception 'profile_required' using errcode = '42501'; end if;

  if exists (select 1 from public.banned_terms t where v_body ilike '%' || t.term || '%') then
    raise exception 'blocked_content' using errcode = '22023';
  end if;

  -- Serialize sends per user so the rate limit cannot be raced.
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));

  select * into v_last from public.messages
   where user_id = v_uid and room = p_room
   order by created_at desc limit 1;
  if found then
    if v_last.created_at > now() - interval '3 seconds' then
      raise exception 'rate_limited' using errcode = '53400';
    end if;
    if v_last.body = v_body and v_last.created_at > now() - interval '30 seconds' then
      raise exception 'duplicate' using errcode = '23505';
    end if;
  end if;

  select count(*) into v_count from public.messages
   where user_id = v_uid and created_at > now() - interval '1 minute';
  if v_count >= 12 then raise exception 'rate_limited' using errcode = '53400'; end if;

  v_key := private.author_key(v_uid, p_room);

  insert into public.messages (room, user_id, body, is_anonymous, display_name, avatar_url, author_key)
  values (
    p_room, v_uid, v_body, p_anonymous,
    case when p_anonymous then private.anon_name(v_key) else v_profile.display_name end,
    case when p_anonymous then null else v_profile.avatar_url end,
    v_key)
  returning * into v_msg;

  perform realtime.send(private.message_payload(v_msg), 'message', 'room:' || p_room, true);
  return private.message_payload(v_msg);
end;
$$;

create function public.recent_messages(p_room text)
returns setof jsonb
language sql stable security definer set search_path = ''
as $$
  select private.message_payload(s.m) from (
    select m from public.messages m
     where m.room = p_room
       and not m.hidden
       and m.created_at > now() - interval '10 minutes'
       and not exists (select 1 from public.blocks b
                        where b.blocker = auth.uid() and b.blocked = m.user_id)
     order by m.created_at desc
     limit 50
  ) s
  order by (s.m).created_at asc;
$$;

-- Author keys (for today, in this room) of everyone the caller has blocked,
-- so the client can drop live messages from them, anonymous or not.
create function public.blocked_keys(p_room text)
returns text[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(private.author_key(b.blocked, p_room)), '{}')
    from public.blocks b where b.blocker = auth.uid();
$$;

create function public.my_anon_name(p_room text)
returns text
language sql stable security definer set search_path = ''
as $$
  select private.anon_name(private.author_key(auth.uid(), p_room));
$$;

create function public.report_message(p_message_id uuid, p_reason text)
returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_msg public.messages;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_msg from public.messages where id = p_message_id;
  if not found then return; end if;

  insert into public.reports (message_id, reporter, reason)
  values (p_message_id, auth.uid(), p_reason)
  on conflict (message_id, reporter) do nothing;

  if not v_msg.hidden and
     (select count(distinct reporter) from public.reports where message_id = p_message_id) >= 3 then
    update public.messages set hidden = true where id = p_message_id;
    perform realtime.send(jsonb_build_object('id', p_message_id), 'hide', 'room:' || v_msg.room, true);
  end if;
end;
$$;

create function public.block_message_author(p_message_id uuid)
returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_msg public.messages;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_msg from public.messages where id = p_message_id;
  if not found or v_msg.user_id = auth.uid() then return; end if;
  insert into public.blocks (blocker, blocked, label)
  values (auth.uid(), v_msg.user_id, v_msg.display_name)
  on conflict (blocker, blocked) do nothing;
end;
$$;

create function public.list_blocks()
returns table (id uuid, label text, created_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select b.id, b.label, b.created_at from public.blocks b
   where b.blocker = auth.uid() order by b.created_at desc;
$$;

create function public.unblock(p_block_id uuid)
returns void
language sql volatile security definer set search_path = ''
as $$
  delete from public.blocks where id = p_block_id and blocker = auth.uid();
$$;

revoke execute on all functions in schema private from public, anon, authenticated;
revoke execute on function
  public.send_message(text, text, boolean), public.recent_messages(text), public.blocked_keys(text),
  public.my_anon_name(text), public.report_message(uuid, text), public.block_message_author(uuid),
  public.list_blocks(), public.unblock(uuid)
  from public, anon;
grant execute on function
  public.send_message(text, text, boolean), public.recent_messages(text), public.blocked_keys(text),
  public.my_anon_name(text), public.report_message(uuid, text), public.block_message_author(uuid),
  public.list_blocks(), public.unblock(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime authorization for private room channels
-- ---------------------------------------------------------------------------

-- Any signed-in user may listen to a room channel and its presence.
create policy "signed-in users receive room channels"
  on realtime.messages for select to authenticated
  using (realtime.topic() like 'room:%');

-- Clients may only publish presence; chat messages come from send_message.
create policy "signed-in users track presence in rooms"
  on realtime.messages for insert to authenticated
  with check (realtime.topic() like 'room:%' and realtime.messages.extension = 'presence');

-- ---------------------------------------------------------------------------
-- Retention
-- ---------------------------------------------------------------------------

select cron.schedule(
  'kuro-purge-messages',
  '*/10 * * * *',
  $$ delete from public.messages where created_at < now() - interval '24 hours' $$
);
