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

-- matricula.status — ciclo de vida da matrícula. 'ativa' é o único
-- estado inicial: matricula tem um único data_matricula, sem coluna para
-- separar "solicitado" de "confirmado", então o INSERT já é o ato de
-- matricular. 'trancada', 'cancelada' e 'concluida' são desfechos
-- possíveis a partir de 'ativa' — não uma sequência linear entre si.

CREATE TYPE status_mat_t AS ENUM (
    'ativa',
    'trancada',
    'cancelada',
    'concluida'
);

-- historico.situacao — estado da matrícula ao longo do período, não só o
-- resultado terminal: a linha de historico nasce junto com a matrícula
-- ('cursando', notas ainda nulas — ver nota_t) e é atualizada conforme o
-- período avança. 'trancada' cobre quem abandona no meio do caminho, sem
-- nota final lançada. Reprovação separada por causa: nota
-- (reprovado_nota) ou frequência (reprovado_falta), podendo ocorrer as
-- duas ao mesmo tempo (reprovado_nota_falta) — por isso são rótulos
-- exaustivos de um único enum, e não dois booleanos independentes.

CREATE TYPE situacao_t AS ENUM (
    'cursando',
    'trancada',
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

-- ---------------------------------------------------------------------
-- 4. Tipo range de horário
-- ---------------------------------------------------------------------

-- turma_horario.faixa — timerange não é nativo do PG 17, por isso o
-- range e a função de distância abaixo precisam existir antes da coluna
-- que os usa (02_tabelas.sql).
--
-- subtype = time (sem fuso): horário de aula é hora de parede — o mesmo
-- 10h vale igual em qualquer situação, não deve deslizar com
-- fuso/horário de verão. timetz é desaconselhado pela própria
-- documentação do Postgres por esse motivo.

-- time_subtype_diff dá ao GiST uma métrica de distância entre dois
-- horários (em segundos). Sem ela o índice ainda funciona — subtype_diff
-- é opcional — mas o GiST particiona as páginas às cegas, sem saber que
-- 08:00 e 08:05 estão mais próximos entre si do que 08:00 e 22:00.
--
-- IMMUTABLE: mesma entrada sempre produz a mesma saída — exigido para
-- qualquer função usada dentro da definição de um índice/tipo indexável.
-- STRICT: retorna NULL de imediato se x ou y for NULL, sem executar o
-- corpo. Os limites de um range de fato não são NULL (ausência de limite
-- é o conceito de "unbounded", diferente disso); STRICT aqui é trava de
-- segurança, não uma regra de negócio.

CREATE FUNCTION time_subtype_diff(x time, y time)
RETURNS float8
AS $$
    SELECT EXTRACT(EPOCH FROM (x - y))::float8;
$$ LANGUAGE sql IMMUTABLE STRICT;

COMMENT ON FUNCTION time_subtype_diff(time, time) IS
    'Distância em segundos entre dois horários; usada pelo GiST de timerange.';

CREATE TYPE timerange AS RANGE (
    subtype = time,
    subtype_diff = time_subtype_diff
);

COMMENT ON TYPE timerange IS
    'Faixa de horário de aula. Convenção do grupo: sempre semiaberta [) — '
    'aula que termina 10:40 não conflita com aula que começa 10:40.';
