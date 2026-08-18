-- =====================================================================
-- 01_tipos_dominios.sql
-- CREATE TYPE / CREATE DOMAIN / CREATE EXTENSION exigidos pelo modelo
-- Frente: Modelagem Física e Desempenho
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================

-- Pré-condição: base `matricula` vazia (docker compose down -v && up -d).
-- Os scripts não são idempotentes de propósito: DROP TYPE ... CASCADE
-- removeria em silêncio as colunas que usam o tipo. Reset = recriar a base.

-- =====================================================================

-- ----------------------------------------------------------------------
-- 1. Extensão
-- ----------------------------------------------------------------------

-- btree_gist ensina ao GiST os operadores de igualdade dos tipos escalares
-- (smallint, integer). Sem ela o EXCLUDE de turma_horario não pode combinar
-- sala_id WITH = e faixa WITH && no mesmo índice: o range já tem suporte
-- GiST nativo, os escalares não.
--
-- IF NOT EXISTS aqui não contradiz "scripts não idempotentes": é uma
-- extensão compartilhada do cluster, não um tipo do esquema — recriá-la
-- não tem o efeito colateral destrutivo do DROP TYPE ... CASCADE.

CREATE EXTENSION IF NOT EXISTS btree_gist;

