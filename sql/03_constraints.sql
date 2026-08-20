-- =====================================================================
-- 03_constraints.sql
-- PK, FK, UNIQUE, CHECK e EXCLUDE das 16 tabelas, via ALTER TABLE — depois
-- que 02_tabelas.sql já criou todas as tabelas (shape puro: coluna, tipo,
-- NOT NULL, DEFAULT, coluna gerada).
-- Frente: Modelagem Física e Desempenho
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================
--
-- Pré-requisito: 01 e 02 já rodados. Depende de btree_gist (01) para o
-- EXCLUDE de turma_horario.
--
-- Ordem: segue a mesma ordem de tabelas de 02_tabelas.sql. Isso importa
-- pra uma dependência real: a UNIQUE (id, curso_id) de curriculo precisa
-- existir antes da FK composta de aluno que a referencia — por isso
-- curriculo vem antes de aluno aqui, igual em 02.

-- ============================================================
-- CAMPUS
-- ============================================================

ALTER TABLE campus
    -- Identificador único do campus.
    ADD CONSTRAINT pk_campus PRIMARY KEY (id),

    -- Não permite dois campi com o mesmo nome.
    ADD CONSTRAINT uq_campus_nome UNIQUE (nome),

    -- Impede nome vazio ou apenas com espaços.
    ADD CONSTRAINT ck_campus_nome_preenchido
        CHECK (length(btrim(nome)) > 0),

    -- Impede cidade vazia ou apenas com espaços.
    ADD CONSTRAINT ck_campus_cidade_preenchida
        CHECK (length(btrim(cidade)) > 0);

-- ============================================================
-- DISCIPLINA
-- ============================================================

ALTER TABLE disciplina
    -- Identificador único da disciplina.
    ADD CONSTRAINT pk_disciplina PRIMARY KEY (id),

    -- Não permite disciplinas com o mesmo código.
    ADD CONSTRAINT uq_disciplina_codigo UNIQUE (codigo),

    -- Impede código vazio ou apenas com espaços.
    ADD CONSTRAINT ck_disciplina_codigo_preenchido
        CHECK (length(btrim(codigo)) > 0),

    -- Impede nome vazio ou apenas com espaços.
    ADD CONSTRAINT ck_disciplina_nome_preenchido
        CHECK (length(btrim(nome)) > 0),

    -- As cargas horárias não podem ser negativas.
    -- Permite uma delas ser 0, por exemplo, disciplina 100% teórica.
    ADD CONSTRAINT ck_disciplina_ch_nao_negativa
        CHECK (ch_teorica >= 0 AND ch_pratica >= 0),

    -- Garante que a carga horária total seja maior que zero.
    -- Ex.: 0 + 0 = 0 não é permitido.
    ADD CONSTRAINT ck_disciplina_ch_total_positiva
        CHECK (ch_total > 0);

-- ============================================================
-- PERIODO_LETIVO
-- ============================================================

ALTER TABLE periodo_letivo
    -- Identificador único do período.
    ADD CONSTRAINT pk_periodo_letivo PRIMARY KEY (id),

    -- Não permite dois períodos com o mesmo ano e semestre.
    ADD CONSTRAINT uq_periodo_letivo_ano_semestre UNIQUE (ano, semestre),

    -- Permite apenas o primeiro ou segundo semestre.
    ADD CONSTRAINT ck_periodo_letivo_semestre_valido
        CHECK (semestre IN (1, 2)),

    -- Evita anos inválidos ou erros de digitação.
    ADD CONSTRAINT ck_periodo_letivo_ano_valido
        CHECK (ano BETWEEN 2000 AND 2100),

    -- A data final deve ser posterior à data inicial.
    ADD CONSTRAINT ck_periodo_letivo_intervalo
        CHECK (data_fim > data_inicio);

