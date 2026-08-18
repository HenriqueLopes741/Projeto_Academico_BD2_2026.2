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

-- ----------------------------------------------------------------------
-- 2. Tipos enumerados
-- ----------------------------------------------------------------------

-- A ordem dos rótulos define a ordenação do tipo (ORDER BY usa a ordem de
-- declaração, não a alfabética). Onde existe sequência natural, ela está
-- respeitada. Rótulos sem acento e em minúsculo: são case e accent
-- sensitive, e qualquer divergência quebra a carga em 04_carga.sql.

-- sala.tipo — classifica o espaço físico. Não guarda capacidade nem
-- equipamento (isso é sala.capacidade); serve para casar disciplina
-- prática/teórica com o tipo de sala na alocação de turma_horario.

CREATE TYPE tipo_sala_t AS ENUM (
    'teorica',
    'laboratorio',
    'auditorio'
);

-- turma.turno — turno declarado da turma, não o horário exato. O horário
-- de fato (dia da semana + faixa) mora em turma_horario; turno é a
-- informação "de vitrine" usada em busca/filtro de oferta.

CREATE TYPE turno_t AS ENUM (
    'matutino',
    'vespertino',
    'noturno'
);

-- pre_requisito.vinculo — natureza da relação entre disciplina e
-- requisito na tabela auto-relacionada. pre_requisito: precisa ter sido
-- cursada/aprovada antes; co_requisito: pode ser cursada no mesmo
-- período; equivalencia: uma dispensa a outra (ex.: disciplina
-- reformulada substituindo a antiga no currículo).

CREATE TYPE vinculo_t AS ENUM (
    'pre_requisito',
    'co_requisito',
    'equivalencia'
);

-- curriculo_disciplina.tipo — papel da disciplina dentro daquele
-- currículo específico. Fica na tabela de ligação, e não em disciplina,
-- porque a mesma disciplina pode ser obrigatória num currículo e
-- optativa em outro.
CREATE TYPE tipo_disc_t AS ENUM (
    'obrigatoria',
    'optativa',
    'eletiva'
);

-- matricula.status — ciclo de vida da matrícula, na ordem em que os
-- estados acontecem.

CREATE TYPE status_mat_t AS ENUM (
    'solicitada',
    'confirmada',
    'trancada',
    'cancelada',
    'concluida'
);

-- historico.situacao — resultado final da matrícula após o período
-- encerrar. Reprovação separada por causa: nota (reprovado_nota) ou
-- frequência (reprovado_falta), podendo ocorrer as duas ao mesmo tempo
-- (reprovado_nota_falta) — por isso são rótulos exaustivos de um único
-- enum, e não dois booleanos independentes.

CREATE TYPE situacao_t AS ENUM (
    'cursando',
    'aprovado',
    'reprovado_nota',
    'reprovado_falta',
    'reprovado_nota_falta'
);

-- ---------------------------------------------------------------------
-- 3. Domínios numéricos
-- ---------------------------------------------------------------------

-- historico.nota_a1 / nota_a2 / nota_p3 — numeric(4,2) acompanha o tipo
-- de historico.media_final, definido no modelo: as três notas e a média
-- ficam no mesmo tipo base, sem coerção implícita na coluna gerada.
-- numeric(4,2) por si só permitiria até 99,99; é o CHECK que restringe a
-- faixa a 0-10, não a precisão numérica declarada no tipo.
-- O CHECK não rejeita NULL — nota ainda não lançada é ausência de dado,
-- não violação. Obrigatoriedade, se houver, é NOT NULL na coluna (02).

CREATE DOMAIN nota_t AS numeric(4,2)
    CONSTRAINT ck_nota_t_faixa CHECK (VALUE >= 0 AND VALUE <= 10);

-- historico.frequencia — percentual de presença, faixa 0-100. 5 dígitos
-- totais (numeric(5,2)) para caber 100,00 sem estourar a precisão; com
-- numeric(4,2) o valor máximo representável seria 99,99.

CREATE DOMAIN pct_t AS numeric(5,2)
    CONSTRAINT ck_pct_t_faixa CHECK (VALUE >= 0 AND VALUE <= 100);

