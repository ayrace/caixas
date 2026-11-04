-- Execute no SQL Editor do Supabase. Configure usuários via Supabase Auth.
create extension if not exists pgcrypto;
create table if not exists public.estoque_destinos (
 id uuid primary key default gen_random_uuid(), nome text not null unique,
 grupo text not null, tipo text not null check(tipo in ('tecnico','cluster','outros')),
 ativo boolean not null default true, auth_uid uuid unique references auth.users(id)
);
create table if not exists public.estoque_movimentos (
 id uuid primary key default gen_random_uuid(), criado_em timestamptz not null default now(),
 data_operacao date not null default current_date,
 tipo text not null check(tipo in ('entrada','distribuicao','uso','devolucao','ajuste_entrada','ajuste_saida')),
 destino_id uuid references public.estoque_destinos(id), quantidade integer not null check(quantidade>0),
 incidente text, endereco text, servico text, observacao text,
 autor_uid uuid not null default auth.uid(),
 constraint uso_comprovado check(tipo <> 'uso' or (destino_id is not null and nullif(trim(incidente),'') is not null and nullif(trim(endereco),'') is not null and nullif(trim(servico),'') is not null))
);
create index if not exists idx_estoque_mov_dest on public.estoque_movimentos(destino_id,criado_em);
create index if not exists idx_estoque_mov_data on public.estoque_movimentos(data_operacao);
create table if not exists public.estoque_gestores (uid uuid primary key references auth.users(id));
create or replace function public.estoque_saldo_central() returns integer language sql stable security definer set search_path=public as $$
 select coalesce(sum(case when tipo in ('entrada','devolucao','ajuste_entrada') then quantidade when tipo in ('distribuicao','ajuste_saida') then -quantidade else 0 end),0)::integer from public.estoque_movimentos
$$;
create or replace function public.estoque_saldo_destino(p_destino uuid) returns integer language sql stable security definer set search_path=public as $$
 select coalesce(sum(case when tipo='distribuicao' then quantidade when tipo in ('uso','devolucao') then -quantidade else 0 end),0)::integer from public.estoque_movimentos where destino_id=p_destino
$$;
create or replace function public.estoque_registrar(p_tipo text,p_destino uuid,p_quantidade integer,p_data date,p_incidente text default null,p_endereco text default null,p_servico text default null,p_observacao text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_gestor boolean; v_dono boolean; v_id uuid; v_saldo integer;
begin
 perform pg_advisory_xact_lock(719331);
 v_gestor:=exists(select 1 from public.estoque_gestores where uid=auth.uid());
 v_dono:=exists(select 1 from public.estoque_destinos where id=p_destino and auth_uid=auth.uid() and ativo);
 if auth.uid() is null then raise exception 'Autenticação obrigatória'; end if;
 if p_quantidade is null or p_quantidade<=0 or p_data is null then raise exception 'Quantidade e data inválidas'; end if;
 if p_tipo not in ('entrada','distribuicao','uso','devolucao','ajuste_entrada','ajuste_saida') then raise exception 'Operação inválida'; end if;
 if p_tipo <> 'uso' and not v_gestor then raise exception 'Somente gestor pode executar esta operação'; end if;
 if p_tipo='uso' and not (v_gestor or v_dono) then raise exception 'Destino não autorizado'; end if;
 if p_tipo in ('uso','distribuicao','devolucao') and not exists(select 1 from public.estoque_destinos where id=p_destino and ativo) then raise exception 'Destino inválido'; end if;
 if p_tipo in ('entrada','ajuste_entrada','ajuste_saida') and p_destino is not null then raise exception 'Entrada/ajuste central não usa destino'; end if;
 if p_tipo='distribuicao' then
   if p_quantidade<>2 then raise exception 'Lote obrigatório de 2 caixas'; end if;
   if public.estoque_saldo_destino(p_destino)<>0 then raise exception 'Técnico com saldo pendente'; end if;
   if public.estoque_saldo_central()<p_quantidade then raise exception 'Estoque central insuficiente'; end if;
 end if;
 if p_tipo in ('uso','devolucao') and public.estoque_saldo_destino(p_destino)<p_quantidade then raise exception 'Saldo do destino insuficiente'; end if;
 if p_tipo='ajuste_saida' and public.estoque_saldo_central()<p_quantidade then raise exception 'Estoque central insuficiente'; end if;
 if p_tipo='uso' and (nullif(trim(p_incidente),'') is null or nullif(trim(p_endereco),'') is null or nullif(trim(p_servico),'') is null) then raise exception 'Incidente, endereço e serviço obrigatórios'; end if;
 insert into public.estoque_movimentos(tipo,destino_id,quantidade,data_operacao,incidente,endereco,servico,observacao)
 values(p_tipo,p_destino,p_quantidade,p_data,p_incidente,p_endereco,p_servico,p_observacao) returning id into v_id;
 return v_id;
end $$;
alter table public.estoque_destinos enable row level security;
alter table public.estoque_movimentos enable row level security;
alter table public.estoque_gestores enable row level security;
create policy "destinos leitura autenticada" on public.estoque_destinos for select to authenticated using(true);
create policy "movimentos leitura autorizada" on public.estoque_movimentos for select to authenticated using(
 exists(select 1 from public.estoque_gestores where uid=auth.uid()) or exists(select 1 from public.estoque_destinos where id=destino_id and auth_uid=auth.uid())
);
create policy "gestores leitura propria" on public.estoque_gestores for select to authenticated using(uid=auth.uid());
revoke all on function public.estoque_registrar(text,uuid,integer,date,text,text,text,text) from public,anon;
grant execute on function public.estoque_registrar(text,uuid,integer,date,text,text,text,text) to authenticated;
revoke all on function public.estoque_saldo_central() from public,anon;
revoke all on function public.estoque_saldo_destino(uuid) from public,anon;
-- Saldos são calculados apenas dentro da função de movimentação; não expor RPCs de saldo.
insert into public.estoque_destinos(nome,grupo,tipo) values
('BERNARDO KM','KM','tecnico'),('ÉVERTON KM','KM','tecnico'),('EDUARDO KM','KM','tecnico'),('LEONARDO KM','KM','tecnico'),('FRANCISCO KM','KM','tecnico'),('LONGARAY KM','KM','tecnico'),('PAULO KM','KM','tecnico'),('VANDERLEI KM','KM','tecnico'),('BRUNO JLE','JLE','tecnico'),('MARCOS JLE','JLE','tecnico'),('MÁRCIO JLE','JLE','tecnico'),('CLUSTER NHO','NHO','cluster'),('CLUSTER KDK','KDK','cluster'),('OUTROS','Outros','outros') on conflict(nome) do nothing;
-- Após criar seu usuário gestor no Auth, habilite-o manualmente:
-- insert into public.estoque_gestores(uid) values ('UUID-DO-USUARIO-GESTOR');
-- Vincule cada técnico ao seu login: update public.estoque_destinos set auth_uid='UUID' where nome='BERNARDO KM';
