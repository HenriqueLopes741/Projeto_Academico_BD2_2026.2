-- =====================================================================
-- 01_ddl.sql
-- DDL completo do modelo lógico v4, em um único script: extensão, tipos,
-- domínios, range e as 16 tabelas com suas constraints (PK, FK, UNIQUE,
-- CHECK, EXCLUDE) declaradas dentro do próprio CREATE TABLE.
-- Frente: Modelagem Física e Desempenho
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================
--
-- Pré-condição: base `matricula` vazia (docker compose down -v && up -d).
-- O script não é idempotente de propósito: DROP TYPE ... CASCADE
-- removeria em silêncio as colunas que usam o tipo. Reset = recriar a base.
--
-- Convenção de nomes (modelo lógico v4):
--   tabela   = tb_<nome>             (ex.: tb_campus)
--   atributo = <atributo>_<tabela>   (ex.: nome_campus)
--   PK       = id_<tabela>           (ex.: id_campus)
--   FK       = mesmo nome da PK que referencia (id_campus em tb_curso)
--   Duas FK para a mesma tabela: a segunda leva o papel no nome
--   (id_disciplina_requisito em tb_pre_requisito).
--   Constraints: pk_/fk_/uq_/ck_/ex_<tabela sem prefixo>_<assunto>.
--
-- O diagrama escreve TB_campus; sem aspas o PostgreSQL guarda tb_campus,
-- e é assim que o nome aparece aqui e no catálogo.
--
-- Ordem dos atributos (igual ao diagrama): PK → FK → char/varchar/text →
-- numéricos → demais (data, boolean, enum, jsonb). Colunas geradas ficam
-- logo depois das colunas de que dependem.
--
-- Ordem das tabelas == ordem de dependência de FK. Como cada FK é
-- declarada no CREATE TABLE, a tabela referenciada precisa existir antes:
--   1. tb_campus, tb_disciplina, tb_periodo_letivo, tb_professor
--   2. tb_curso, tb_sala, tb_feriado, tb_turma
--   3. tb_curriculo, tb_turma_horario
--   4. tb_aluno, tb_curriculo_disciplina
--   5. tb_matricula, tb_pre_requisito
--   6. tb_historico, tb_log_matricula

-- =====================================================================
-- PARTE 1 — EXTENSÃO, TIPOS E DOMÍNIOS
-- =====================================================================

-- ----------------------------------------------------------------------
-- 1.1 Extensão
-- ----------------------------------------------------------------------

-- btree_gist ensina ao GiST os operadores de igualdade dos tipos escalares
-- (smallint, integer). Sem ela o EXCLUDE de tb_turma_horario não pode
-- combinar id_sala WITH =, dia_semana_turma_horario WITH = e
-- faixa_turma_horario WITH && no mesmo índice: o range já tem suporte GiST
-- nativo, os escalares não.
--
-- IF NOT EXISTS aqui não contradiz "script não idempotente": é uma
-- extensão compartilhada do cluster, não um tipo do esquema — recriá-la
-- não tem o efeito colateral destrutivo do DROP TYPE ... CASCADE.

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ----------------------------------------------------------------------
-- 1.2 Tipos enumerados
-- ----------------------------------------------------------------------

-- A ordem dos rótulos define a ordenação do tipo (ORDER BY usa a ordem de
-- declaração, não a alfabética). Onde existe sequência natural, ela está
-- respeitada. Rótulos sem acento e em minúsculo: são case e accent
-- sensitive, e qualquer divergência quebra a carga.

-- tb_sala.tipo_sala — classifica o espaço físico. Não guarda capacidade
-- (isso é capacidade_sala); serve para casar disciplina prática/teórica
-- com o tipo de sala na alocação de tb_turma_horario.
CREATE TYPE tipo_sala_t AS ENUM (
    'teorica',
    'laboratorio',
    'auditorio'
);

-- tb_turma.turno_turma — turno declarado da turma, não o horário exato. O
-- horário de fato (dia + faixa) mora em tb_turma_horario; turno é a
-- informação "de vitrine" usada em busca/filtro de oferta.
CREATE TYPE turno_t AS ENUM (
    'matutino',
    'vespertino',
    'noturno'
);

-- tb_pre_requisito.vinculo_pre_requisito — natureza da relação.
-- pre_requisito: precisa ter sido cursada/aprovada antes; co_requisito:
-- pode ser cursada no mesmo período; equivalencia: uma dispensa a outra.
CREATE TYPE vinculo_t AS ENUM (
    'pre_requisito',
    'co_requisito',
    'equivalencia'
);

-- tb_curriculo_disciplina.tipo_curriculo_disciplina — papel da disciplina
-- naquele currículo. Fica na associativa, e não em tb_disciplina, porque
-- a mesma disciplina pode ser obrigatória num currículo e optativa em outro.
CREATE TYPE tipo_disc_t AS ENUM (
    'obrigatoria',
    'optativa',
    'eletiva'
);

-- tb_matricula.status_matricula — ciclo de vida da matrícula. 'ativa' é o
-- único estado inicial: o INSERT já é o ato de matricular. 'trancada',
-- 'cancelada' e 'concluida' são desfechos possíveis a partir de 'ativa' —
-- não uma sequência linear entre si.
CREATE TYPE status_mat_t AS ENUM (
    'ativa',
    'trancada',
    'cancelada',
    'concluida'
);

-- tb_historico.situacao_historico — estado ao longo do período, não só o
-- resultado terminal: a linha nasce 'cursando' (notas nulas) e é
-- atualizada conforme o período avança. Reprovação separada por causa,
-- podendo ocorrer as duas ao mesmo tempo (reprovado_nota_falta) — por isso
-- são rótulos exaustivos de um único enum, e não dois booleanos.
CREATE TYPE situacao_t AS ENUM (
    'cursando',
    'trancada',
    'aprovado',
    'reprovado_nota',
    'reprovado_falta',
    'reprovado_nota_falta'
);

-- ----------------------------------------------------------------------
-- 1.3 Domínios numéricos
-- ----------------------------------------------------------------------

-- Notas A1/A2/P3. numeric(4,2) é o mesmo tipo de media_final_historico,
-- sem coerção implícita na coluna gerada. A precisão sozinha permitiria
-- 99,99; é o CHECK que restringe a 0-10. O CHECK não rejeita NULL — nota
-- ainda não lançada é ausência de dado, não violação.
CREATE DOMAIN nota_t AS numeric(4,2)
    CONSTRAINT ck_nota_t_faixa CHECK (VALUE >= 0 AND VALUE <= 10);

-- Percentual de presença, 0-100. numeric(5,2) para caber 100,00; com
-- numeric(4,2) o máximo seria 99,99.
CREATE DOMAIN pct_t AS numeric(5,2)
    CONSTRAINT ck_pct_t_faixa CHECK (VALUE >= 0 AND VALUE <= 100);

-- ----------------------------------------------------------------------
-- 1.4 Tipo range de horário
-- ----------------------------------------------------------------------

-- timerange não é nativo do PG 17. subtype = time (sem fuso): horário de
-- aula é hora de parede, não deve deslizar com fuso/horário de verão.
--
-- time_subtype_diff dá ao GiST uma métrica de distância (em segundos).
-- É opcional, mas sem ela o GiST particiona as páginas às cegas.
-- IMMUTABLE: exigido para função usada em tipo indexável.
-- STRICT: retorna NULL de imediato se x ou y for NULL (trava de segurança).

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

-- =====================================================================
-- PARTE 2 — TABELAS E CONSTRAINTS
-- =====================================================================
--
-- Padrões repetidos em todas as tabelas (explicados uma vez aqui):
--   * GENERATED BY DEFAULT AS IDENTITY: o id é gerado, mas aceita valor
--     manual na carga.
--   * ck_*_preenchido(a): CHECK (length(btrim(col)) > 0) — impede texto
--     vazio ou só com espaços, que NOT NULL sozinho deixaria passar.
--   * FKs com ON UPDATE CASCADE: troca de id no pai acompanha no filho.
--     ON DELETE RESTRICT por padrão; CASCADE só onde o filho é parte
--     composicional do pai (comentado em cada caso).
--   * UNIQUE é case-sensitive: "Asa Sul" e "asa sul" são distintos. Nos
--     e-mails, o CHECK de minúsculas torna a UNIQUE simples equivalente a
--     uma case-insensitive.

-- ============================================================
-- TB_CAMPUS
-- ============================================================
-- Raiz do modelo: não depende de ninguém. Referenciada por tb_curso,
-- tb_sala e tb_feriado.

CREATE TABLE tb_campus (
    id_campus      smallint    GENERATED BY DEFAULT AS IDENTITY,
    nome_campus    varchar(60) NOT NULL,
    cidade_campus  varchar(60) NOT NULL,

    CONSTRAINT pk_campus PRIMARY KEY (id_campus),
    CONSTRAINT uq_campus_nome UNIQUE (nome_campus),
    CONSTRAINT ck_campus_nome_preenchido
        CHECK (length(btrim(nome_campus)) > 0),
    CONSTRAINT ck_campus_cidade_preenchida
        CHECK (length(btrim(cidade_campus)) > 0)
);

COMMENT ON TABLE tb_campus IS
    'Unidades físicas do centro universitário. Raiz da hierarquia campus > sala.';
COMMENT ON COLUMN tb_campus.nome_campus IS
    'Único e case-sensitive: "Asa Sul" e "asa sul" são valores distintos.';

-- ============================================================
-- TB_DISCIPLINA
-- ============================================================
-- Catálogo independente de curso. O vínculo com currículo vive em
-- tb_curriculo_disciplina.

CREATE TABLE tb_disciplina (
    id_disciplina          integer      GENERATED BY DEFAULT AS IDENTITY,
    codigo_disciplina      varchar(10)  NOT NULL,
    nome_disciplina        varchar(120) NOT NULL,
    -- Pode ser cadastrada depois.
    ementa_disciplina      text,
    ch_teorica_disciplina  smallint     NOT NULL,
    ch_pratica_disciplina  smallint     NOT NULL,
    -- Coluna gerada: 40 teóricas + 20 práticas = 60.
    ch_total_disciplina    smallint     GENERATED ALWAYS AS
        (ch_teorica_disciplina + ch_pratica_disciplina) STORED,

    CONSTRAINT pk_disciplina PRIMARY KEY (id_disciplina),
    CONSTRAINT uq_disciplina_codigo UNIQUE (codigo_disciplina),
    CONSTRAINT ck_disciplina_codigo_preenchido
        CHECK (length(btrim(codigo_disciplina)) > 0),
    CONSTRAINT ck_disciplina_nome_preenchido
        CHECK (length(btrim(nome_disciplina)) > 0),
    -- Uma das parcelas pode ser 0 (disciplina 100% teórica).
    CONSTRAINT ck_disciplina_ch_nao_negativa
        CHECK (ch_teorica_disciplina >= 0 AND ch_pratica_disciplina >= 0),
    -- Mas a soma não: 0 + 0 não é disciplina.
    CONSTRAINT ck_disciplina_ch_total_positiva
        CHECK (ch_total_disciplina > 0)
);

COMMENT ON TABLE tb_disciplina IS
    'Catálogo de disciplinas. Independe de curso e currículo: o vínculo '
    'disciplina-currículo vive em tb_curriculo_disciplina.';
COMMENT ON COLUMN tb_disciplina.ch_total_disciplina IS
    'Gerada STORED a partir das parcelas. Parcelas NOT NULL garantem que '
    'nunca resulte NULL; ck_disciplina_ch_total_positiva impede soma zero.';

-- ============================================================
-- TB_PERIODO_LETIVO
-- ============================================================

CREATE TABLE tb_periodo_letivo (
    -- Surrogate: não codifica ano/semestre.
    id_periodo_letivo           smallint GENERATED BY DEFAULT AS IDENTITY,
    ano_periodo_letivo          smallint NOT NULL,
    -- 1 = primeiro semestre, 2 = segundo semestre.
    semestre_periodo_letivo     smallint NOT NULL,
    data_inicio_periodo_letivo  date     NOT NULL,
    data_fim_periodo_letivo     date     NOT NULL,

    CONSTRAINT pk_periodo_letivo PRIMARY KEY (id_periodo_letivo),
    CONSTRAINT uq_periodo_letivo_ano_semestre
        UNIQUE (ano_periodo_letivo, semestre_periodo_letivo),
    CONSTRAINT ck_periodo_letivo_semestre_valido
        CHECK (semestre_periodo_letivo IN (1, 2)),
    -- Faixa defensiva contra erro de digitação.
    CONSTRAINT ck_periodo_letivo_ano_valido
        CHECK (ano_periodo_letivo BETWEEN 2000 AND 2100),
    CONSTRAINT ck_periodo_letivo_intervalo
        CHECK (data_fim_periodo_letivo > data_inicio_periodo_letivo)
);

COMMENT ON TABLE tb_periodo_letivo IS
    'Semestres letivos. (ano_periodo_letivo, semestre_periodo_letivo) é a chave '
    'natural; id_periodo_letivo é surrogate.';
COMMENT ON COLUMN tb_periodo_letivo.id_periodo_letivo IS
    'Surrogate deliberado. Não codifica ano/semestre para não acoplar '
    'identidade a dado de negócio.';

-- ============================================================
-- TB_PROFESSOR
-- ============================================================

CREATE TABLE tb_professor (
    id_professor         integer      GENERATED BY DEFAULT AS IDENTITY,
    matricula_professor  varchar(12)  NOT NULL,
    nome_professor       varchar(120) NOT NULL,
    email_professor      varchar(120) NOT NULL,
    -- Opcional: pode não estar cadastrada.
    titulacao_professor  varchar(20),

    CONSTRAINT pk_professor PRIMARY KEY (id_professor),
    CONSTRAINT uq_professor_matricula UNIQUE (matricula_professor),
    CONSTRAINT uq_professor_email UNIQUE (email_professor),
    CONSTRAINT ck_professor_matricula_preenchida
        CHECK (length(btrim(matricula_professor)) > 0),
    CONSTRAINT ck_professor_nome_preenchido
        CHECK (length(btrim(nome_professor)) > 0),
    -- joao@email.com é válido; Joao@email.com não.
    CONSTRAINT ck_professor_email_minusculo
        CHECK (email_professor = lower(email_professor)),
    -- Validação básica de formato, não RFC completa.
    CONSTRAINT ck_professor_email_formato
        CHECK (email_professor LIKE '%_@_%._%')
);

COMMENT ON TABLE tb_professor IS
    'Corpo docente. Referenciada por tb_turma.id_professor.';
COMMENT ON COLUMN tb_professor.email_professor IS
    'Armazenado sempre em minúsculas (ck_professor_email_minusculo), o que '
    'torna a UNIQUE simples equivalente a uma UNIQUE case-insensitive.';
COMMENT ON COLUMN tb_professor.titulacao_professor IS
    'varchar por definição do modelo, não enum. Sem CHECK de domínio para '
    'não quebrar a carga com variações de grafia.';

-- ============================================================
-- TB_CURSO
-- ============================================================
-- Primeira tabela com dependência (tb_campus). Referenciada por
-- tb_curriculo e tb_aluno.

CREATE TABLE tb_curso (
    id_curso        smallint     GENERATED BY DEFAULT AS IDENTITY,
    id_campus       smallint     NOT NULL,
    codigo_curso    varchar(10)  NOT NULL,
    nome_curso      varchar(120) NOT NULL,
    -- Bacharelado, Tecnólogo... varchar, não enum: dados reais variam.
    grau_curso      varchar(20),
    ch_total_curso  smallint     NOT NULL,

    CONSTRAINT pk_curso PRIMARY KEY (id_curso),
    CONSTRAINT uq_curso_codigo UNIQUE (codigo_curso),
    CONSTRAINT ck_curso_codigo_preenchido
        CHECK (length(btrim(codigo_curso)) > 0),
    CONSTRAINT ck_curso_nome_preenchido
        CHECK (length(btrim(nome_curso)) > 0),
    CONSTRAINT ck_curso_ch_total_positiva
        CHECK (ch_total_curso > 0),
    -- RESTRICT: não apaga campus que ainda oferece cursos.
    CONSTRAINT fk_curso_campus
        FOREIGN KEY (id_campus) REFERENCES tb_campus (id_campus)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE tb_curso IS
    'Cursos de graduação. Pertence a um campus; agrupa currículos.';
COMMENT ON COLUMN tb_curso.ch_total_curso IS
    'Denormalizado: carga horária oficial do curso. Não é coluna gerada '
    'porque dependeria de tb_curriculo_disciplina (outras linhas), o que '
    'coluna gerada não permite. smallint, mesmo tipo de '
    'tb_disciplina.ch_total_disciplina.';
COMMENT ON COLUMN tb_curso.codigo_curso IS
    'Único e case-sensitive, mesmo padrão de tb_campus.nome_campus: "ADS" e '
    '"ads" são valores distintos para o UNIQUE.';
COMMENT ON COLUMN tb_curso.grau_curso IS
    'varchar por definição do modelo, não enum. Sem CHECK de domínio para '
    'não quebrar a carga com variações de grafia — mesmo motivo de '
    'tb_professor.titulacao_professor.';

-- ============================================================
-- TB_SALA
-- ============================================================

CREATE TABLE tb_sala (
    -- integer porque tb_turma_horario.id_sala também é integer.
    id_sala          integer     GENERATED BY DEFAULT AS IDENTITY,
    id_campus        smallint    NOT NULL,
    -- A-101, LAB-01...
    codigo_sala      varchar(10) NOT NULL,
    capacidade_sala  smallint    NOT NULL,
    tipo_sala        tipo_sala_t NOT NULL,

    CONSTRAINT pk_sala PRIMARY KEY (id_sala),
    -- Único por campus, não globalmente: Campus 1 → A-101 | Campus 2 → A-101.
    CONSTRAINT uq_sala_campus_codigo UNIQUE (id_campus, codigo_sala),
    CONSTRAINT ck_sala_codigo_preenchido
        CHECK (length(btrim(codigo_sala)) > 0),
    CONSTRAINT ck_sala_capacidade
        CHECK (capacidade_sala BETWEEN 1 AND 1000),
    -- RESTRICT: não apaga campus que ainda possui salas.
    CONSTRAINT fk_sala_campus
        FOREIGN KEY (id_campus) REFERENCES tb_campus (id_campus)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE tb_sala IS
    'Espaços físicos. Referenciada por tb_turma_horario, onde o EXCLUDE impede '
    'duas turmas na mesma sala em horários sobrepostos.';
COMMENT ON COLUMN tb_sala.codigo_sala IS
    'Único por campus, não globalmente: o mesmo código pode se repetir em '
    'campi diferentes (uq_sala_campus_codigo).';

-- ============================================================
-- TB_FERIADO
-- ============================================================
-- Tabela folha: ninguém a referencia. Consumida por consultas de
-- calendário (dias letivos efetivos de um período).

CREATE TABLE tb_feriado (
    id_feriado         integer      GENERATED BY DEFAULT AS IDENTITY,
    -- NULL = feriado nacional (todos os campi); preenchido = feriado local.
    id_campus          smallint,
    descricao_feriado  varchar(120) NOT NULL,
    data_feriado       date         NOT NULL,

    CONSTRAINT pk_feriado PRIMARY KEY (id_feriado),
    -- NULLS NOT DISTINCT trata NULL como igual a NULL, então o mesmo
    -- feriado nacional não entra duas vezes na mesma data:
    --   (21/04/2026, NULL) → só uma vez.
    --   (15/08/2026, 1)    → só uma vez no campus 1.
    --   (15/08/2026, 2)    → permitido, outro campus.
    CONSTRAINT uq_feriado_data_campus
        UNIQUE NULLS NOT DISTINCT (data_feriado, id_campus),
    CONSTRAINT ck_feriado_descricao_preenchida
        CHECK (length(btrim(descricao_feriado)) > 0),
    -- RESTRICT: não apaga campus que possui feriados locais.
    CONSTRAINT fk_feriado_campus
        FOREIGN KEY (id_campus) REFERENCES tb_campus (id_campus)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE tb_feriado IS
    'Feriados que suspendem aula. Sem FK para tb_periodo_letivo: a relação com '
    'o semestre é por intervalo de data, resolvida em consulta.';
COMMENT ON COLUMN tb_feriado.id_campus IS
    'NULL = feriado nacional (todos os campi). Preenchido = feriado local '
    'daquele campus. A UNIQUE usa NULLS NOT DISTINCT para que a duplicata '
    'de feriado nacional na mesma data seja rejeitada.';

-- ============================================================
-- TB_TURMA
-- ============================================================
-- Oferta concreta de uma disciplina num período. Referenciada por
-- tb_turma_horario e tb_matricula.

CREATE TABLE tb_turma (
    id_turma           integer     GENERATED BY DEFAULT AS IDENTITY,
    id_disciplina      integer     NOT NULL,
    id_periodo_letivo  smallint    NOT NULL,
    -- Obrigatório: os dados da carga têm professor em todas as turmas.
    id_professor       integer     NOT NULL,
    codigo_turma       varchar(15) NOT NULL,
    vagas_turma        smallint    NOT NULL,
    turno_turma        turno_t     NOT NULL,

    CONSTRAINT pk_turma PRIMARY KEY (id_turma),
    -- O código se repete a cada semestre, mas não dentro do mesmo:
    -- CCODM2B pode existir em 2026/1 e em 2026/2.
    CONSTRAINT uq_turma_periodo_codigo
        UNIQUE (id_periodo_letivo, codigo_turma),
    -- Redundante como unicidade (id_turma já é PK), mas é o alvo da FK
    -- composta de tb_turma_horario: FK precisa de PK ou UNIQUE cobrindo
    -- exatamente as colunas referenciadas. Mesmo padrão de
    -- uq_curriculo_id_curso.
    CONSTRAINT uq_turma_id_periodo
        UNIQUE (id_turma, id_periodo_letivo),
    CONSTRAINT ck_turma_codigo_preenchido
        CHECK (length(btrim(codigo_turma)) > 0),
    CONSTRAINT ck_turma_vagas
        CHECK (vagas_turma BETWEEN 1 AND 300),
    CONSTRAINT fk_turma_disciplina
        FOREIGN KEY (id_disciplina) REFERENCES tb_disciplina (id_disciplina)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_turma_periodo_letivo
        FOREIGN KEY (id_periodo_letivo) REFERENCES tb_periodo_letivo (id_periodo_letivo)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_turma_professor
        FOREIGN KEY (id_professor) REFERENCES tb_professor (id_professor)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE tb_turma IS
    'Oferta de disciplina em um período letivo. Tabela central do Marco 2: '
    'vagas_turma é o recurso disputado na anomalia de concorrência.';
COMMENT ON COLUMN tb_turma.vagas_turma IS
    'Capacidade ofertada. A regra COUNT(tb_matricula) <= vagas_turma NÃO é '
    'garantida por constraint — depende de outra tabela. É resolvida por '
    'transação com bloqueio explícito ou nível de isolamento adequado (Marco 2).';
COMMENT ON COLUMN tb_turma.codigo_turma IS
    'Único por período letivo, não globalmente: o mesmo código se repete a '
    'cada semestre (uq_turma_periodo_codigo).';

-- ============================================================
-- TB_CURRICULO
-- ============================================================
-- Grade de um curso, por ano de vigência. Referenciada por
-- tb_curriculo_disciplina e pela FK composta de tb_aluno.

CREATE TABLE tb_curriculo (
    id_curriculo            integer  GENERATED BY DEFAULT AS IDENTITY,
    id_curso                smallint NOT NULL,
    ano_vigencia_curriculo  smallint NOT NULL,
    ativo_curriculo         boolean  NOT NULL DEFAULT true,

    CONSTRAINT pk_curriculo PRIMARY KEY (id_curriculo),
    -- Um curso não tem duas grades no mesmo ano de vigência.
    CONSTRAINT uq_curriculo_curso_ano
        UNIQUE (id_curso, ano_vigencia_curriculo),
    -- Alvo da FK composta (id_curriculo, id_curso) de tb_aluno.
    CONSTRAINT uq_curriculo_id_curso
        UNIQUE (id_curriculo, id_curso),
    CONSTRAINT ck_curriculo_ano_vigencia
        CHECK (ano_vigencia_curriculo BETWEEN 2000 AND 2100),
    CONSTRAINT fk_curriculo_curso
        FOREIGN KEY (id_curso) REFERENCES tb_curso (id_curso)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE tb_curriculo IS
    'Grades curriculares por curso e ano de vigência. Um curso acumula '
    'várias grades ao longo do tempo; alunos ficam vinculados à sua.';
COMMENT ON CONSTRAINT uq_curriculo_id_curso ON tb_curriculo IS
    'Aparentemente redundante (id_curriculo já é PK). Existe para servir de alvo à FK '
    'composta (id_curriculo, id_curso) de tb_aluno, que garante coerência entre '
    'o curso do aluno e o curso do seu currículo. A ordem das colunas na FK '
    'precisa casar com a ordem desta UNIQUE (id_curriculo, id_curso).';

-- ============================================================
-- TB_TURMA_HORARIO
-- ============================================================
-- Horário de aula de uma turma: dia, faixa e sala.

CREATE TABLE tb_turma_horario (
    id_turma_horario          integer   GENERATED BY DEFAULT AS IDENTITY,
    id_turma                  integer   NOT NULL,
    -- Cópia do período da turma, para o EXCLUDE poder separar semestres
    -- (EXCLUDE só enxerga colunas da própria linha). A FK composta
    -- garante que o valor é sempre o mesmo da turma.
    id_periodo_letivo         smallint  NOT NULL,
    id_sala                   integer   NOT NULL,
    -- Padrão ISO: 1 = segunda ... 7 = domingo.
    dia_semana_turma_horario  smallint  NOT NULL,
    faixa_turma_horario       timerange NOT NULL,

    CONSTRAINT pk_turma_horario PRIMARY KEY (id_turma_horario),
    CONSTRAINT ck_turma_horario_dia_semana
        CHECK (dia_semana_turma_horario BETWEEN 1 AND 7),
    -- Faixa com início e fim, não vazia.
    CONSTRAINT ck_turma_horario_faixa_valida
        CHECK (NOT isempty(faixa_turma_horario)
           AND lower(faixa_turma_horario) IS NOT NULL
           AND upper(faixa_turma_horario) IS NOT NULL),
    -- Impede duas turmas na mesma sala, no mesmo período letivo e no mesmo
    -- dia, com faixas sobrepostas. Com id_periodo_letivo no EXCLUDE, a mesma
    -- sala e horário podem ser reusados no semestre seguinte.
    -- btree_gist permite '=' nas colunas escalares.
    CONSTRAINT ex_turma_horario_sala_ocupada
        EXCLUDE USING gist (
            id_sala                  WITH =,
            id_periodo_letivo        WITH =,
            dia_semana_turma_horario WITH =,
            faixa_turma_horario      WITH &&
        ),
    -- FK COMPOSTA: além de a turma existir, o período gravado aqui tem de
    -- ser o da turma. Sem ela, o EXCLUDE poderia comparar semestres errados.
    -- CASCADE: horário é parte da turma; ON UPDATE leva junto troca de período.
    CONSTRAINT fk_turma_horario_turma
        FOREIGN KEY (id_turma, id_periodo_letivo)
        REFERENCES tb_turma (id_turma, id_periodo_letivo)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_turma_horario_sala
        FOREIGN KEY (id_sala) REFERENCES tb_sala (id_sala)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE tb_turma_horario IS
    'Grade de horários. O EXCLUDE impede duas turmas na mesma sala, no mesmo '
    'período letivo e dia, em faixas sobrepostas — regra entre linhas, '
    'impossível via CHECK.';
COMMENT ON COLUMN tb_turma_horario.id_periodo_letivo IS
    'Cópia controlada de tb_turma.id_periodo_letivo (FK composta). Existe '
    'para o EXCLUDE permitir a mesma sala e horário em semestres diferentes.';
COMMENT ON COLUMN tb_turma_horario.faixa_turma_horario IS
    'timerange criado na Parte 1 deste script (não é tipo nativo). Usar '
    'sempre limite [) para que aulas contíguas não conflitem.';
COMMENT ON CONSTRAINT ex_turma_horario_sala_ocupada ON tb_turma_horario IS
    'Escopo: sala + período letivo + dia + faixa horária. id_periodo_letivo é '
    'copiado de tb_turma e mantido igual pela FK composta fk_turma_horario_turma. '
    'Não cobre conflito de professor nem a mesma turma com horários '
    'sobrepostos em salas diferentes (conferidos na carga).';

-- ============================================================
-- TB_ALUNO
-- ============================================================

CREATE TABLE tb_aluno (
    id_aluno          integer      GENERATED BY DEFAULT AS IDENTITY,
    id_curso          smallint     NOT NULL,
    id_curriculo      integer      NOT NULL,
    matricula_aluno   varchar(12)  NOT NULL,
    nome_aluno        varchar(120) NOT NULL,
    -- Só dígitos, sem pontuação.
    cpf_aluno         char(11)     NOT NULL,
    email_aluno       varchar(120) NOT NULL,
    nascimento_aluno  date         NOT NULL,
    ingresso_aluno    date         NOT NULL,
    -- Desligamento é ativo = false, nunca DELETE (ver fk_matricula_aluno).
    ativo_aluno       boolean      NOT NULL DEFAULT true,

    CONSTRAINT pk_aluno PRIMARY KEY (id_aluno),
    CONSTRAINT uq_aluno_matricula UNIQUE (matricula_aluno),
    CONSTRAINT uq_aluno_cpf UNIQUE (cpf_aluno),
    CONSTRAINT uq_aluno_email UNIQUE (email_aluno),
    CONSTRAINT ck_aluno_matricula_preenchida
        CHECK (length(btrim(matricula_aluno)) > 0),
    CONSTRAINT ck_aluno_nome_preenchido
        CHECK (length(btrim(nome_aluno)) > 0),
    -- Único CHECK de formato do projeto: CPF tem formato fixo (11 dígitos),
    -- ao contrário de código/matrícula, onde regex quebraria a carga real.
    -- Dígito verificador é regra de aplicação.
    CONSTRAINT ck_aluno_cpf_valido
        CHECK (cpf_aluno ~ '^[0-9]{11}$'),
    -- Mesma política de tb_professor: normaliza em vez de índice funcional.
    CONSTRAINT ck_aluno_email_minusculo
        CHECK (email_aluno = lower(email_aluno)),
    CONSTRAINT ck_aluno_email_formato
        CHECK (email_aluno LIKE '%_@_%._%'),
    CONSTRAINT ck_aluno_ingresso_apos_nascimento
        CHECK (ingresso_aluno > nascimento_aluno),
    -- Piso defensivo contra digitação, sem inventar idade mínima.
    CONSTRAINT ck_aluno_nascimento_plausivel
        CHECK (nascimento_aluno BETWEEN '1900-01-01' AND current_date),
    -- FK COMPOSTA — o ponto da tabela. Isoladas, as duas colunas aceitariam
    -- aluno de Computação com currículo de Direito; o PAR só existe em
    -- tb_curriculo se o currículo for daquele curso. Substitui a FK simples
    -- para tb_curriculo.
    CONSTRAINT fk_aluno_curriculo_curso
        FOREIGN KEY (id_curriculo, id_curso)
        REFERENCES tb_curriculo (id_curriculo, id_curso)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    -- FK simples para tb_curso: não é redundante. A composta garante o par;
    -- esta garante id_curso isolado, e é o que o modelo declara.
    CONSTRAINT fk_aluno_curso
        FOREIGN KEY (id_curso) REFERENCES tb_curso (id_curso)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE tb_aluno IS
    'Alunos matriculados. A FK composta (id_curriculo, id_curso) impede a '
    'incoerência entre o curso do aluno e o curso do seu currículo.';
COMMENT ON COLUMN tb_aluno.cpf_aluno IS
    'char(11), somente dígitos, sem pontuação. Dígito verificador não é '
    'validado no banco — é regra de aplicação.';
COMMENT ON CONSTRAINT fk_aluno_curriculo_curso ON tb_aluno IS
    'Depende de uq_curriculo_id_curso em tb_curriculo. Se aquela UNIQUE for '
    'removida, esta FK deixa de ser declarável.';

-- ============================================================
-- TB_CURRICULO_DISCIPLINA
-- ============================================================
-- Associativa N:N entre currículo e disciplina: quais disciplinas compõem
-- uma grade, em que período, com que natureza.

CREATE TABLE tb_curriculo_disciplina (
    id_curriculo                  integer     NOT NULL,
    id_disciplina                 integer     NOT NULL,
    -- Semestre da GRADE (1º, 2º...), não o tb_periodo_letivo calendário.
    periodo_curriculo_disciplina  smallint    NOT NULL,
    tipo_curriculo_disciplina     tipo_disc_t NOT NULL,

    -- PK composta é a própria unicidade: uma disciplina aparece no máximo
    -- uma vez por currículo.
    CONSTRAINT pk_curriculo_disciplina
        PRIMARY KEY (id_curriculo, id_disciplina),
    -- Piso rígido, teto folgado (graduação vai até ~10 períodos).
    CONSTRAINT ck_curriculo_disciplina_periodo
        CHECK (periodo_curriculo_disciplina BETWEEN 1 AND 20),
    -- CASCADE: a linha é parte da grade; apagar a grade apaga a composição.
    CONSTRAINT fk_curriculo_disciplina_curriculo
        FOREIGN KEY (id_curriculo) REFERENCES tb_curriculo (id_curriculo)
        ON DELETE CASCADE ON UPDATE CASCADE,
    -- RESTRICT: disciplina é catálogo compartilhado; apagá-la esvaziaria
    -- currículos em silêncio.
    CONSTRAINT fk_curriculo_disciplina_disciplina
        FOREIGN KEY (id_disciplina) REFERENCES tb_disciplina (id_disciplina)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE tb_curriculo_disciplina IS
    'Composição da grade curricular. Junto com tb_pre_requisito, é a base da '
    'consulta recursiva das disciplinas que um aluno já pode cursar.';
COMMENT ON COLUMN tb_curriculo_disciplina.periodo_curriculo_disciplina IS
    'Semestre da GRADE (1º, 2º...), não o tb_periodo_letivo calendário.';

-- ============================================================
-- TB_MATRICULA
-- ============================================================

CREATE TABLE tb_matricula (
    id_matricula      integer      GENERATED BY DEFAULT AS IDENTITY,
    id_aluno          integer      NOT NULL,
    id_turma          integer      NOT NULL,
    -- timestamptz: armazena em UTC e converte na leitura.
    data_matricula    timestamptz  NOT NULL DEFAULT now(),
    status_matricula  status_mat_t NOT NULL,

    CONSTRAINT pk_matricula PRIMARY KEY (id_matricula),
    -- Indispensável para o Marco 2: duplicata corromperia a contagem de vagas.
    CONSTRAINT uq_matricula_aluno_turma
        UNIQUE (id_aluno, id_turma),
    -- Data futura é erro de carga ou de relógio.
    CONSTRAINT ck_matricula_data_nao_futura
        CHECK (data_matricula <= now()),
    -- RESTRICT: matrícula é registro acadêmico com valor próprio, não parte
    -- do aluno. Com CASCADE, apagar um aluno levaria matrícula e histórico
    -- junto. A cadeia para aqui; tb_historico → tb_matricula segue CASCADE
    -- porque ali a relação é composicional (1:1).
    CONSTRAINT fk_matricula_aluno
        FOREIGN KEY (id_aluno) REFERENCES tb_aluno (id_aluno)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_matricula_turma
        FOREIGN KEY (id_turma) REFERENCES tb_turma (id_turma)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE tb_matricula IS
    'Vínculo aluno-turma. uq_matricula_aluno_turma, UQ (id_aluno, id_turma) '
    'do modelo, é indispensável: sem ela a contagem de vagas do Marco 2 é '
    'corrompida por duplicatas.';
COMMENT ON COLUMN tb_matricula.status_matricula IS
    'Trancamento e cancelamento são mudanças de status, não DELETE. A linha '
    'permanece para preservar o histórico.';

-- ============================================================
-- TB_PRE_REQUISITO
-- ============================================================
-- Auto-relacionamento N:N de disciplina, por currículo: a mesma disciplina
-- pode ter requisitos diferentes em cada curso (ex.: Linguagens Formais
-- exige Teoria da Computação em CCO e Estrutura de Dados em ECO).
-- Vem depois de tb_curriculo_disciplina, alvo das duas FKs compostas.

CREATE TABLE tb_pre_requisito (
    id_curriculo             integer   NOT NULL,
    -- Disciplina que exige (vem depois na sequência).
    id_disciplina            integer   NOT NULL,
    -- Disciplina exigida.
    id_disciplina_requisito  integer   NOT NULL,
    vinculo_pre_requisito    vinculo_t NOT NULL,

    -- A mesma exigência não entra duas vezes na mesma grade, mas pode
    -- existir em currículos diferentes.
    CONSTRAINT pk_pre_requisito
        PRIMARY KEY (id_curriculo, id_disciplina, id_disciplina_requisito),
    -- Impede A → A. Não impede ciclos maiores (A → B → A).
    CONSTRAINT ck_pre_requisito_sem_autorreferencia
        CHECK (id_disciplina <> id_disciplina_requisito),
    -- FK COMPOSTA: a disciplina que exige tem de estar nesta grade.
    -- CASCADE: tirá-la da grade apaga as exigências dela.
    CONSTRAINT fk_pre_requisito_disciplina
        FOREIGN KEY (id_curriculo, id_disciplina)
        REFERENCES tb_curriculo_disciplina (id_curriculo, id_disciplina)
        ON DELETE CASCADE ON UPDATE CASCADE,
    -- FK COMPOSTA: o requisito também tem de estar na MESMA grade (as duas
    -- FKs compartilham id_curriculo). RESTRICT: não tira da grade uma
    -- disciplina que ainda é requisito de outra.
    CONSTRAINT fk_pre_requisito_requisito
        FOREIGN KEY (id_curriculo, id_disciplina_requisito)
        REFERENCES tb_curriculo_disciplina (id_curriculo, id_disciplina)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE tb_pre_requisito IS
    'Auto-relacionamento N:N de disciplina, dentro de um currículo. Base da '
    'consulta recursiva da árvore de pré-requisitos. Ciclos maiores que 1 NÃO '
    'são impedidos por constraint — é limitação conceitual, não de sintaxe.';
COMMENT ON COLUMN tb_pre_requisito.id_curriculo IS
    'Currículo em que a exigência vale. Faz parte das duas FKs compostas para '
    'tb_curriculo_disciplina: disciplina e requisito têm de estar na mesma grade.';
COMMENT ON COLUMN tb_pre_requisito.id_disciplina IS
    'Disciplina que exige. ON DELETE CASCADE: tirar a disciplina da grade '
    'apaga suas exigências, que não fazem sentido sem ela.';
COMMENT ON COLUMN tb_pre_requisito.id_disciplina_requisito IS
    'Disciplina exigida. ON DELETE RESTRICT: tirá-la da grade quebraria a '
    'sequência de outras disciplinas silenciosamente.';

-- ============================================================
-- TB_HISTORICO
-- ============================================================
-- 1:1 com tb_matricula: notas e situação.

CREATE TABLE tb_historico (
    id_historico           integer    GENERATED BY DEFAULT AS IDENTITY,
    -- FK + UNIQUE = relação 1:1.
    id_matricula           integer    NOT NULL,
    -- nota_t já carrega o CHECK 0-10: uma definição, três usos.
    nota_a1_historico      nota_t,
    nota_a2_historico      nota_t,
    -- A maioria dos alunos não faz P3.
    nota_p3_historico      nota_t,
    frequencia_historico   pct_t,
    -- Coluna gerada (STORED, única opção no PG 17). A1 pesa 40%, A2 60%.
    -- P3, se houver, substitui a menor das duas e herda o peso do slot.
    -- NULL se faltar A1 ou A2: ausência de nota não é zero.
    media_final_historico  numeric(4,2) GENERATED ALWAYS AS (
        CASE
            -- Guarda antes de qualquer comparação: comparar com NULL dá
            -- desconhecido, e o ELSE capturaria esse caso.
            WHEN nota_a1_historico IS NULL OR nota_a2_historico IS NULL
                THEN NULL
            WHEN nota_p3_historico IS NULL
                THEN nota_a1_historico * 0.4 + nota_a2_historico * 0.6
            WHEN nota_a1_historico <= nota_a2_historico
                THEN nota_p3_historico * 0.4 + nota_a2_historico * 0.6
            ELSE nota_a1_historico * 0.4 + nota_p3_historico * 0.6
        END
    ) STORED,
    situacao_historico     situacao_t NOT NULL,

    CONSTRAINT pk_historico PRIMARY KEY (id_historico),
    -- O UQ do modelo: garante o 1:1.
    CONSTRAINT uq_historico_matricula UNIQUE (id_matricula),
    -- CASCADE: sem a matrícula, a linha de notas não tem sujeito.
    CONSTRAINT fk_historico_matricula
        FOREIGN KEY (id_matricula) REFERENCES tb_matricula (id_matricula)
        ON DELETE CASCADE ON UPDATE CASCADE
);

COMMENT ON TABLE tb_historico IS
    'Notas e situação por matrícula. Relação 1:1 garantida por '
    'uq_historico_matricula.';
COMMENT ON COLUMN tb_historico.media_final_historico IS
    'A1 40%, A2 60%. P3, quando presente, substitui a menor das duas e herda '
    'o peso do slot. NULL se faltar nota — ausência não é zero.';
COMMENT ON COLUMN tb_historico.nota_p3_historico IS
    'Nullable por natureza: a maioria dos alunos não faz prova substitutiva.';

-- ============================================================
-- TB_LOG_MATRICULA
-- ============================================================
-- Trilha de auditoria. Alimentada por trigger no Marco 2.

CREATE TABLE tb_log_matricula (
    -- bigint: log cresce por EVENTO, não por entidade — volume ordens de
    -- grandeza maior que o de dados.
    id_log_matricula           bigint      GENERATED BY DEFAULT AS IDENTITY,
    -- SEM FK, deliberado: com FK, apagar a matrícula apagaria (CASCADE) ou
    -- impediria (RESTRICT) o registro justamente da remoção. Log guarda
    -- fato histórico, não referência viva.
    id_matricula               integer     NOT NULL,
    -- varchar e não enum: o conjunto de ações cresce, e enum não permite
    -- remover valor.
    acao_log_matricula         varchar(20) NOT NULL,
    -- Tipo 'name' (63 bytes), o mesmo de current_user.
    usuario_log_matricula      name        NOT NULL DEFAULT current_user,
    ocorrido_em_log_matricula  timestamptz NOT NULL DEFAULT now(),
    -- jsonb (binário, indexável) e não json (texto puro, mais lento).
    detalhe_log_matricula      jsonb,

    CONSTRAINT pk_log_matricula PRIMARY KEY (id_log_matricula),
    CONSTRAINT ck_log_matricula_acao_preenchida
        CHECK (length(btrim(acao_log_matricula)) > 0),
    -- Objeto no topo, não array nem escalar: detalhe->>'chave' sempre faz
    -- sentido. jsonb_typeof é IMMUTABLE, então serve em CHECK.
    CONSTRAINT ck_log_matricula_detalhe_objeto
        CHECK (detalhe_log_matricula IS NULL
            OR jsonb_typeof(detalhe_log_matricula) = 'object')
);

COMMENT ON TABLE tb_log_matricula IS
    'Auditoria de matrícula. Ausência de FK em id_matricula é deliberada: '
    'o log deve sobreviver à remoção da linha auditada.';
COMMENT ON COLUMN tb_log_matricula.id_matricula IS
    'Referência histórica, não FK. Pode apontar para matrícula já removida — '
    'é justamente o caso que a auditoria precisa registrar.';
COMMENT ON COLUMN tb_log_matricula.detalhe_log_matricula IS
    'jsonb com o contexto do evento (estado anterior, novo status, origem). '
    'Estrutura livre por design: cada ação registra o que lhe é relevante.';
