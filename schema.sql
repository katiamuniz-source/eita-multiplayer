-- EITA! multiplayer — esquema inicial
-- Cole todo este arquivo no Supabase SQL Editor e execute.
-- Este MVP implementa criação/entrada em salas, presença por heartbeat,
-- lista de participantes e controles do organizador. Rodadas e votação serão a próxima etapa.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.eita_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (length(code) = 6),
  host_name text not null,
  host_token_hash text not null,
  status text not null default 'waiting' check (status in ('waiting','active','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.eita_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.eita_rooms(id) on delete cascade,
  nickname text not null,
  token_hash text not null,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists eita_players_room_id_idx on public.eita_players(room_id);
create index if not exists eita_rooms_code_idx on public.eita_rooms(code);

alter table public.eita_rooms enable row level security;
alter table public.eita_players enable row level security;
revoke all on public.eita_rooms from anon, authenticated;
revoke all on public.eita_players from anon, authenticated;

create or replace function public.eita_create_room(p_host_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text;
  v_token text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_room_id uuid;
  v_attempt int := 0;
begin
  if length(trim(coalesce(p_host_name,''))) = 0 or length(trim(p_host_name)) > 18 then
    raise exception 'Digite um apelido de até 18 caracteres.';
  end if;
  loop
    v_code := upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,6));
    begin
      insert into public.eita_rooms(code,host_name,host_token_hash)
      values(v_code,trim(p_host_name),encode(extensions.digest(v_token,'sha256'),'hex'))
      returning id into v_room_id;
      exit;
    exception when unique_violation then
      v_attempt := v_attempt + 1;
      if v_attempt > 10 then raise exception 'Não foi possível gerar um código. Tente novamente.'; end if;
    end;
  end loop;
  insert into public.eita_players(room_id,nickname,token_hash)
  values(v_room_id,trim(p_host_name),encode(extensions.digest(v_token,'sha256'),'hex'));
  return jsonb_build_object('code',v_code,'host_token',v_token);
end;
$$;

create or replace function public.eita_join_room(p_code text, p_nickname text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_room public.eita_rooms%rowtype;
  v_token text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_count int;
begin
  if length(trim(coalesce(p_nickname,''))) = 0 or length(trim(p_nickname)) > 18 then
    raise exception 'Digite um apelido de até 18 caracteres.';
  end if;
  select * into v_room from public.eita_rooms where code = upper(trim(p_code));
  if not found then raise exception 'Sala não encontrada. Confira o código.'; end if;
  if v_room.status <> 'waiting' then raise exception 'Esta sala não está aceitando novos jogadores.'; end if;
  select count(*) into v_count from public.eita_players where room_id=v_room.id;
  if v_count >= 30 then raise exception 'A sala já atingiu o limite de 30 participantes.'; end if;
  insert into public.eita_players(room_id,nickname,token_hash)
  values(v_room.id,trim(p_nickname),encode(extensions.digest(v_token,'sha256'),'hex'));
  return jsonb_build_object('code',v_room.code,'player_token',v_token);
end;
$$;

create or replace function public.eita_ping_player(p_code text, p_player_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_player_id uuid;
begin
  select p.id into v_player_id
  from public.eita_players p join public.eita_rooms r on r.id=p.room_id
  where r.code=upper(trim(p_code))
    and p.token_hash=encode(extensions.digest(p_player_token,'sha256'),'hex')
    and r.status <> 'closed';
  if v_player_id is null then raise exception 'Sessão de jogador inválida ou sala encerrada.'; end if;
  update public.eita_players set last_seen_at=now() where id=v_player_id;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.eita_room_state(p_code text, p_access_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_room public.eita_rooms%rowtype;
  v_hash text := encode(extensions.digest(p_access_token,'sha256'),'hex');
  v_authorized boolean := false;
  v_players jsonb;
begin
  select * into v_room from public.eita_rooms where code=upper(trim(p_code));
  if not found then raise exception 'Sala não encontrada.'; end if;
  v_authorized := v_room.host_token_hash=v_hash or exists(
    select 1 from public.eita_players where room_id=v_room.id and token_hash=v_hash
  );
  if not v_authorized then raise exception 'Token de acesso inválido.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'nickname',p.nickname,
    'online',(p.last_seen_at > now() - interval '20 seconds'),
    'joined_at',p.joined_at
  ) order by p.joined_at),'[]'::jsonb)
  into v_players
  from public.eita_players p where p.room_id=v_room.id;
  return jsonb_build_object('code',v_room.code,'host_name',v_room.host_name,
    'status',v_room.status,'players',v_players,'created_at',v_room.created_at);
end;
$$;

create or replace function public.eita_start_room(p_code text, p_host_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_room_id uuid;
begin
  update public.eita_rooms set status='active',updated_at=now()
  where code=upper(trim(p_code))
    and host_token_hash=encode(extensions.digest(p_host_token,'sha256'),'hex')
    and status='waiting'
  returning id into v_room_id;
  if v_room_id is null then raise exception 'Não foi possível iniciar. Verifique se você é o organizador e se a sala está aguardando.'; end if;
  return jsonb_build_object('ok',true,'status','active');
end;
$$;

create or replace function public.eita_close_room(p_code text, p_host_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_room_id uuid;
begin
  update public.eita_rooms set status='closed',updated_at=now()
  where code=upper(trim(p_code))
    and host_token_hash=encode(extensions.digest(p_host_token,'sha256'),'hex')
    and status <> 'closed'
  returning id into v_room_id;
  if v_room_id is null then raise exception 'Não foi possível encerrar. Verifique se você é o organizador.'; end if;
  return jsonb_build_object('ok',true,'status','closed');
end;
$$;

revoke all on function public.eita_create_room(text) from public;
revoke all on function public.eita_join_room(text,text) from public;
revoke all on function public.eita_ping_player(text,text) from public;
revoke all on function public.eita_room_state(text,text) from public;
revoke all on function public.eita_start_room(text,text) from public;
revoke all on function public.eita_close_room(text,text) from public;
grant execute on function public.eita_create_room(text) to anon, authenticated;
grant execute on function public.eita_join_room(text,text) to anon, authenticated;
grant execute on function public.eita_ping_player(text,text) to anon, authenticated;
grant execute on function public.eita_room_state(text,text) to anon, authenticated;
grant execute on function public.eita_start_room(text,text) to anon, authenticated;
grant execute on function public.eita_close_room(text,text) to anon, authenticated;
