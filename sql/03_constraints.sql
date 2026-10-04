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
-- pra uma dependência real: a UNIQUE (id_curriculo, id_curso) de curriculo precisa
-- existir antes da FK composta de aluno que a referencia — por isso
-- curriculo vem antes de aluno aqui, igual em 02.

-- ============================================================
-- CAMPUS
-- ============================================================

ALTER TABLE campus
    -- Identificador único do campus.
    ADD CONSTRAINT pk_campus PRIMARY KEY (id_campus),

    -- Não permite dois campi com o mesmo nome.
    ADD CONSTRAINT uq_campus_nome UNIQUE (nome_campus),

    -- Impede nome vazio ou apenas com espaços.
    ADD CONSTRAINT ck_campus_nome_preenchido
        CHECK (length(btrim(nome_campus)) > 0),

    -- Impede cidade vazia ou apenas com espaços.
    ADD CONSTRAINT ck_campus_cidade_preenchida
        CHECK (length(btrim(cidade_campus)) > 0);

-- ============================================================
-- DISCIPLINA
-- ============================================================

ALTER TABLE disciplina
    -- Identificador único da disciplina.
    ADD CONSTRAINT pk_disciplina PRIMARY KEY (id_disciplina),

    -- Não permite disciplinas com o mesmo código.
    ADD CONSTRAINT uq_disciplina_codigo UNIQUE (codigo_disciplina),

    -- Impede código vazio ou apenas com espaços.
    ADD CONSTRAINT ck_disciplina_codigo_preenchido
        CHECK (length(btrim(codigo_disciplina)) > 0),

    -- Impede nome vazio ou apenas com espaços.
    ADD CONSTRAINT ck_disciplina_nome_preenchido
        CHECK (length(btrim(nome_disciplina)) > 0),

    -- As cargas horárias não podem ser negativas.
    -- Permite uma delas ser 0, por exemplo, disciplina 100% teórica.
    ADD CONSTRAINT ck_disciplina_ch_nao_negativa
        CHECK (ch_teorica_disciplina >= 0 AND ch_pratica_disciplina >= 0),

    -- Garante que a carga horária total seja maior que zero.
    -- Ex.: 0 + 0 = 0 não é permitido.
    ADD CONSTRAINT ck_disciplina_ch_total_positiva
        CHECK (ch_total_disciplina > 0);

-- ============================================================
-- PERIODO_LETIVO
-- ============================================================

ALTER TABLE periodo_letivo
    -- Identificador único do período.
    ADD CONSTRAINT pk_periodo_letivo PRIMARY KEY (id_periodo_letivo),

    -- Não permite dois períodos com o mesmo ano e semestre.
    ADD CONSTRAINT uq_periodo_letivo_ano_semestre UNIQUE (ano_periodo_letivo, semestre_periodo_letivo),

    -- Permite apenas o primeiro ou segundo semestre.
    ADD CONSTRAINT ck_periodo_letivo_semestre_valido
        CHECK (semestre_periodo_letivo IN (1, 2)),

    -- Evita anos inválidos ou erros de digitação.
    ADD CONSTRAINT ck_periodo_letivo_ano_valido
        CHECK (ano_periodo_letivo BETWEEN 2000 AND 2100),

    -- A data final deve ser posterior à data inicial.
    ADD CONSTRAINT ck_periodo_letivo_intervalo
        CHECK (data_fim_periodo_letivo > data_inicio_periodo_letivo);

-- ============================================================
-- PROFESSOR
-- ============================================================

ALTER TABLE professor
    -- Identificador único do professor.
    ADD CONSTRAINT pk_professor PRIMARY KEY (id_professor),

    -- Não permite dois professores com a mesma matrícula.
    ADD CONSTRAINT uq_professor_matricula UNIQUE (matricula_professor),

    -- Não permite dois professores com o mesmo email.
    ADD CONSTRAINT uq_professor_email UNIQUE (email_professor),

    -- Impede matrícula vazia ou apenas com espaços.
    ADD CONSTRAINT ck_professor_matricula_preenchida
        CHECK (length(btrim(matricula_professor)) > 0),

    -- Impede nome vazio ou apenas com espaços.
    ADD CONSTRAINT ck_professor_nome_preenchido
        CHECK (length(btrim(nome_professor)) > 0),

    -- Obriga o email a ser armazenado em letras minúsculas.
    -- Ex.: joao@email.com é válido; Joao@email.com não.
    ADD CONSTRAINT ck_professor_email_minusculo
        CHECK (email_professor = lower(email_professor)),

    -- Validação básica do formato do email.
    -- Não é uma validação completa de RFC.
    ADD CONSTRAINT ck_professor_email_formato
        CHECK (email_professor LIKE '%_@_%._%');

-- ============================================================
-- CURSO
-- ============================================================

ALTER TABLE curso
    -- Identifica unicamente cada curso.
    ADD CONSTRAINT pk_curso PRIMARY KEY (id_curso),

    -- Não permite dois cursos com o mesmo código.
    ADD CONSTRAINT uq_curso_codigo UNIQUE (codigo_curso),

    -- Impede código vazio ou apenas com espaços.
    ADD CONSTRAINT ck_curso_codigo_preenchido
        CHECK (length(btrim(codigo_curso)) > 0),

    -- Impede nome vazio ou apenas com espaços.
    ADD CONSTRAINT ck_curso_nome_preenchido
        CHECK (length(btrim(nome_curso)) > 0),

    -- Garante que a carga horária seja maior que zero.
    ADD CONSTRAINT ck_curso_ch_total_positiva
        CHECK (ch_total_curso > 0),

    -- Relaciona o curso ao campus.
    -- RESTRICT impede apagar um campus que ainda possui cursos.
    -- CASCADE atualiza id_campus caso o id_campus seja alterado.
    ADD CONSTRAINT fk_curso_campus
        FOREIGN KEY (id_campus) REFERENCES campus (id_campus)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- SALA
-- ============================================================

ALTER TABLE sala
    -- Identifica unicamente cada sala.
    ADD CONSTRAINT pk_sala PRIMARY KEY (id_sala),

    -- Garante que o código seja único dentro de cada campus.
    -- O mesmo código pode existir em campi diferentes.
    -- Ex.: Campus 1 → A-101 | Campus 2 → A-101.
    ADD CONSTRAINT uq_sala_campus_codigo
        UNIQUE (id_campus, codigo_sala),

    -- Impede código vazio ou apenas com espaços.
    ADD CONSTRAINT ck_sala_codigo_preenchido
        CHECK (length(btrim(codigo_sala)) > 0),

    -- Garante uma capacidade entre 1 e 1000 pessoas.
    -- Evita valores inválidos ou possíveis erros de digitação.
    ADD CONSTRAINT ck_sala_capacidade
        CHECK (capacidade_sala BETWEEN 1 AND 1000),

    -- Relaciona a sala ao campus.
    -- RESTRICT impede apagar um campus que ainda possui salas.
    -- CASCADE atualiza id_campus caso o id_campus seja alterado.
    ADD CONSTRAINT fk_sala_campus
        FOREIGN KEY (id_campus) REFERENCES campus (id_campus)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- FERIADO
-- ============================================================

ALTER TABLE feriado
    -- Identifica unicamente cada feriado.
    ADD CONSTRAINT pk_feriado PRIMARY KEY (id_feriado),

    -- Impede a mesma data para o mesmo campus.
    --
    -- NULLS NOT DISTINCT é importante porque faz NULL ser tratado
    -- como igual a outro NULL.
    --
    -- Assim, não é possível cadastrar duas vezes o mesmo feriado
    -- nacional na mesma data.
    --
    -- Exemplos:
    --   (21/04/2026, NULL) → pode existir apenas uma vez.
    --   (15/08/2026, 1)    → pode existir apenas uma vez no campus 1.
    --   (15/08/2026, 2)    → permitido, pois é outro campus.
    ADD CONSTRAINT uq_feriado_data_campus
        UNIQUE NULLS NOT DISTINCT (data_feriado, id_campus),

    -- Impede descrição vazia ou formada apenas por espaços.
    ADD CONSTRAINT ck_feriado_descricao_preenchida
        CHECK (length(btrim(descricao_feriado)) > 0),

    -- Relaciona o feriado ao campus.
    -- Quando id_campus estiver preenchido, ele precisa existir
    -- em campus.id_campus.
    -- RESTRICT impede apagar um campus que possui feriados locais.
    -- CASCADE atualiza id_campus caso o id_campus seja alterado.
    ADD CONSTRAINT fk_feriado_campus
        FOREIGN KEY (id_campus) REFERENCES campus (id_campus)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- TURMA
-- ============================================================

ALTER TABLE turma
    -- Identifica cada turma de forma única.
    ADD CONSTRAINT pk_turma PRIMARY KEY (id_turma),

    -- O código pode se repetir em períodos diferentes,
    -- mas não pode se repetir dentro do mesmo período.
    -- Ex.: CCODM2B pode existir em 2026/1 e 2026/2.
    ADD CONSTRAINT uq_turma_periodo_codigo
        UNIQUE (id_periodo_letivo, codigo_turma),

    -- Redundante como unicidade (id_turma já é PK), mas é o alvo exigido
    -- pela FK composta de turma_horario: FK precisa de PK ou UNIQUE que
    -- cubra exatamente as colunas referenciadas. Mesmo padrão de
    -- uq_curriculo_id_curso.
    ADD CONSTRAINT uq_turma_id_periodo
        UNIQUE (id_turma, id_periodo_letivo),

    -- Impede código vazio ou formado apenas por espaços.
    ADD CONSTRAINT ck_turma_codigo_preenchido
        CHECK (length(btrim(codigo_turma)) > 0),

    -- Garante pelo menos 1 vaga e limita a 300.
    ADD CONSTRAINT ck_turma_vagas
        CHECK (vagas_turma BETWEEN 1 AND 300),

    -- Relaciona a turma à disciplina.
    -- RESTRICT impede apagar uma disciplina que possui turmas.
    ADD CONSTRAINT fk_turma_disciplina
        FOREIGN KEY (id_disciplina) REFERENCES disciplina (id_disciplina)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    -- Relaciona a turma ao período letivo.
    -- RESTRICT impede apagar um período que possui turmas.
    ADD CONSTRAINT fk_turma_periodo_letivo
        FOREIGN KEY (id_periodo_letivo) REFERENCES periodo_letivo (id_periodo_letivo)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    -- Relaciona a turma ao professor responsável.
    -- RESTRICT impede apagar um professor que possui turmas.
    ADD CONSTRAINT fk_turma_professor
        FOREIGN KEY (id_professor) REFERENCES professor (id_professor)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- CURRICULO
-- ============================================================

ALTER TABLE curriculo
    -- Identifica cada currículo de forma única.
    ADD CONSTRAINT pk_curriculo PRIMARY KEY (id_curriculo),

    -- Um curso não pode possuir duas grades para o mesmo
    -- ano de vigência.
    ADD CONSTRAINT uq_curriculo_curso_ano
        UNIQUE (id_curso, ano_vigencia_curriculo),

    -- Permite que (id_curriculo, id_curso) seja utilizado como alvo
    -- de uma FK composta na tabela aluno.
    ADD CONSTRAINT uq_curriculo_id_curso
        UNIQUE (id_curriculo, id_curso),

    -- Limita o ano de vigência ao intervalo de 2000 a 2100.
    ADD CONSTRAINT ck_curriculo_ano_vigencia
        CHECK (ano_vigencia_curriculo BETWEEN 2000 AND 2100),

    -- Relaciona o currículo ao curso.
    -- RESTRICT impede apagar um curso que possui currículos.
    ADD CONSTRAINT fk_curriculo_curso
        FOREIGN KEY (id_curso) REFERENCES curso (id_curso)
        ON DELETE RESTRICT ON UPDATE CASCADE;

COMMENT ON CONSTRAINT uq_curriculo_id_curso ON curriculo IS
    'Aparentemente redundante (id_curriculo já é PK). Existe para servir de alvo à FK '
    'composta (id_curriculo, id_curso) de aluno, que garante coerência entre '
    'o curso do aluno e o curso do seu currículo. A ordem das colunas na FK '
    'precisa casar com a ordem desta UNIQUE (id_curriculo, id_curso).';

-- ============================================================
-- TURMA_HORARIO
-- ============================================================

ALTER TABLE turma_horario
    -- Identifica cada horário de forma única.
    ADD CONSTRAINT pk_turma_horario PRIMARY KEY (id_turma_horario),

    -- Garante que o dia da semana esteja entre 1 e 7.
    ADD CONSTRAINT ck_turma_horario_dia_semana
        CHECK (dia_semana_turma_horario BETWEEN 1 AND 7),

    -- Garante que a faixa possua início e fim e não seja vazia.
    ADD CONSTRAINT ck_turma_horario_faixa_valida
        CHECK (NOT isempty(faixa_turma_horario)
        AND lower(faixa_turma_horario) IS NOT NULL
        AND upper(faixa_turma_horario) IS NOT NULL),

    -- Impede duas turmas na mesma sala, no mesmo período letivo e no
    -- mesmo dia, com horários sobrepostos. Com id_periodo_letivo no EXCLUDE,
    -- a mesma sala e horário podem ser usados de novo no semestre seguinte.
    -- Utiliza btree_gist para permitir '=' nas colunas escalares.
    ADD CONSTRAINT ex_turma_horario_sala_ocupada
        EXCLUDE USING gist (
            id_sala WITH =,
            id_periodo_letivo WITH =,
            dia_semana_turma_horario WITH =,
            faixa_turma_horario WITH &&
        ),

    -- FK COMPOSTA para turma: além de a turma existir, o período gravado
    -- aqui tem de ser o mesmo da turma. Sem ela, id_periodo_letivo poderia
    -- divergir e o EXCLUDE compararia semestres errados.
    -- CASCADE exclui os horários quando a turma é excluída; ON UPDATE
    -- CASCADE leva junto uma troca de período da turma.
    ADD CONSTRAINT fk_turma_horario_turma
        FOREIGN KEY (id_turma, id_periodo_letivo)
        REFERENCES turma (id_turma, id_periodo_letivo)
        ON DELETE CASCADE ON UPDATE CASCADE,

    -- Relaciona o horário à sala.
    -- RESTRICT impede apagar uma sala que possui horários.
    ADD CONSTRAINT fk_turma_horario_sala
        FOREIGN KEY (id_sala) REFERENCES sala (id_sala)
        ON DELETE RESTRICT ON UPDATE CASCADE;

COMMENT ON CONSTRAINT ex_turma_horario_sala_ocupada ON turma_horario IS
    'Escopo: sala + período letivo + dia + faixa horária. id_periodo_letivo é '
    'copiado de turma e mantido igual pela FK composta fk_turma_horario_turma. '
    'Não cobre conflito de professor nem a mesma turma com horários '
    'sobrepostos em salas diferentes (conferidos na carga, 04).';

-- ============================================================
-- CURRICULO_DISCIPLINA
-- ============================================================

ALTER TABLE curriculo_disciplina
    -- PK composta é a própria unicidade: uma disciplina aparece no máximo
    -- uma vez por currículo. Sem surrogate — o modelo não dá, e o par já
    -- identifica a linha.
    ADD CONSTRAINT pk_curriculo_disciplina
        PRIMARY KEY (id_curriculo, id_disciplina),

    -- Grade de graduação vai até ~10 períodos. Teto folgado, piso rígido:
    -- período 0 ou negativo não existe.
    ADD CONSTRAINT ck_curriculo_disciplina_periodo
        CHECK (periodo_curriculo_disciplina BETWEEN 1 AND 20),

    -- CASCADE: a linha é parte composicional do currículo. Apagar a grade
    -- apaga sua composição, que não significa nada isolada.
    ADD CONSTRAINT fk_curriculo_disciplina_curriculo
        FOREIGN KEY (id_curriculo) REFERENCES curriculo (id_curriculo)
        ON DELETE CASCADE ON UPDATE CASCADE,

    -- RESTRICT: disciplina é catálogo independente, compartilhado por várias
    -- grades. Apagá-la esvaziaria currículos silenciosamente.
    -- Mesma assimetria de pre_requisito: composição em cascata, catálogo restrito.
    ADD CONSTRAINT fk_curriculo_disciplina_disciplina
        FOREIGN KEY (id_disciplina) REFERENCES disciplina (id_disciplina)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- PRE_REQUISITO
-- ============================================================

-- Vem depois de CURRICULO_DISCIPLINA: as FKs compostas abaixo apontam para a
-- PK de curriculo_disciplina, que precisa existir antes.

ALTER TABLE pre_requisito
    -- Chave primária: currículo + par de disciplinas.
    -- Impede que a mesma exigência seja cadastrada duas vezes na mesma grade.
    -- A mesma exigência pode existir em currículos diferentes.
    ADD CONSTRAINT pk_pre_requisito
        PRIMARY KEY (id_curriculo, id_disciplina, id_disciplina_requisito),

    -- Impede que uma disciplina seja requisito dela mesma.
    -- Ex.: Algoritmos I não pode exigir Algoritmos I.
    -- Não impede ciclos maiores, como A → B → A.
    ADD CONSTRAINT ck_pre_requisito_sem_autorreferencia
        CHECK (id_disciplina <> id_disciplina_requisito),

    -- FK COMPOSTA para curriculo_disciplina: a disciplina que exige tem de
    -- estar na grade deste currículo. Substitui a FK simples para disciplina
    -- (a existência da disciplina vem junto, via curriculo_disciplina).
    -- CASCADE: tirar a disciplina da grade apaga as exigências dela.
    ADD CONSTRAINT fk_pre_requisito_disciplina
        FOREIGN KEY (id_curriculo, id_disciplina)
        REFERENCES curriculo_disciplina (id_curriculo, id_disciplina)
        ON DELETE CASCADE ON UPDATE CASCADE,

    -- FK COMPOSTA: o requisito também tem de estar na MESMA grade. As duas
    -- FKs compartilham id_curriculo, então uma exigência nunca mistura
    -- disciplinas de currículos diferentes.
    -- RESTRICT: impede tirar da grade uma disciplina que ainda é requisito
    -- de outra.
    ADD CONSTRAINT fk_pre_requisito_requisito
        FOREIGN KEY (id_curriculo, id_disciplina_requisito)
        REFERENCES curriculo_disciplina (id_curriculo, id_disciplina)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- ALUNO
-- ============================================================

ALTER TABLE aluno
    -- Identifica cada aluno de forma única.
    ADD CONSTRAINT pk_aluno PRIMARY KEY (id_aluno),

    -- Não permite dois alunos com a mesma matrícula.
    ADD CONSTRAINT uq_aluno_matricula UNIQUE (matricula_aluno),

    -- Não permite dois alunos com o mesmo CPF.
    ADD CONSTRAINT uq_aluno_cpf UNIQUE (cpf_aluno),

    -- Não permite dois alunos com o mesmo email.
    ADD CONSTRAINT uq_aluno_email UNIQUE (email_aluno),

    -- Impede matrícula vazia ou apenas com espaços.
    ADD CONSTRAINT ck_aluno_matricula_preenchida
        CHECK (length(btrim(matricula_aluno)) > 0),

    -- Impede nome vazio ou apenas com espaços.
    ADD CONSTRAINT ck_aluno_nome_preenchido
        CHECK (length(btrim(nome_aluno)) > 0),

    -- Único CHECK de formato do projeto, e a exceção se justifica: CPF tem
    -- formato universalmente fixo (11 dígitos), ao contrário de codigo/
    -- matricula, onde regex quebraria a carga real. Não valida dígito
    -- verificador — isso é regra de aplicação, não de integridade estrutural.
    ADD CONSTRAINT ck_aluno_cpf_valido
        CHECK (cpf_aluno ~ '^[0-9]{11}$'),

    -- Mesma política de professor: normaliza em vez de índice funcional.
    ADD CONSTRAINT ck_aluno_email_minusculo
        CHECK (email_aluno = lower(email_aluno)),
    ADD CONSTRAINT ck_aluno_email_formato
        CHECK (email_aluno LIKE '%_@_%._%'),

    -- CHECKs multi-coluna: enxergam a linha inteira.
    ADD CONSTRAINT ck_aluno_ingresso_apos_nascimento
        CHECK (ingresso_aluno > nascimento_aluno),

    -- Piso defensivo contra digitação (1900) sem inventar idade mínima.
    ADD CONSTRAINT ck_aluno_nascimento_plausivel
        CHECK (nascimento_aluno BETWEEN '1900-01-01' AND current_date),

    -- FK COMPOSTA — o ponto da tabela.
    -- As duas colunas isoladas seriam válidas independentemente: nada
    -- impediria aluno no curso de Computação com currículo de Direito.
    -- Esta FK exige que o PAR exista junto em curriculo, o que só é
    -- verdade se o currículo pertencer àquele curso.
    -- Só é declarável porque curriculo tem uq_curriculo_id_curso: FK exige
    -- PK ou UNIQUE cobrindo as colunas referenciadas.
    -- Substitui a FK simples para curriculo — declarar as duas seria redundante.
    ADD CONSTRAINT fk_aluno_curriculo_curso
        FOREIGN KEY (id_curriculo, id_curso) REFERENCES curriculo (id_curriculo, id_curso)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    -- FK simples para curso: NÃO é redundante com a composta. A composta
    -- garante coerência do par; esta garante que id_curso aponta para curso
    -- existente mesmo isoladamente, e é o que o modelo declara.
    ADD CONSTRAINT fk_aluno_curso
        FOREIGN KEY (id_curso) REFERENCES curso (id_curso)
        ON DELETE RESTRICT ON UPDATE CASCADE;

COMMENT ON CONSTRAINT fk_aluno_curriculo_curso ON aluno IS
    'Depende de uq_curriculo_id_curso em curriculo. Se aquela UNIQUE for '
    'removida, esta FK deixa de ser declarável.';

-- ============================================================
-- MATRICULA
-- ============================================================

ALTER TABLE matricula
    -- Identifica cada matrícula de forma única.
    ADD CONSTRAINT pk_matricula PRIMARY KEY (id_matricula),

    -- Impede que um mesmo aluno se matricule duas vezes na mesma turma.
    ADD CONSTRAINT uq_matricula_aluno_turma
        UNIQUE (id_aluno, id_turma),

    -- Matrícula com data futura é erro de carga ou de relógio.
    ADD CONSTRAINT ck_matricula_data_nao_futura
        CHECK (data_matricula <= now()),



    -- RESTRICT: matrícula NÃO é parte composicional do aluno — é registro
    -- acadêmico com valor próprio, que a instituição precisa preservar mesmo
    -- após o desligamento. Com CASCADE, apagar um aluno propagaria por
    -- matricula até historico (também CASCADE), destruindo notas e frequência
    -- em silêncio. Desligamento é ativo = false, nunca DELETE — e é por isso
    -- que a coluna aluno.ativo_aluno existe no modelo.
    -- Note a assimetria deliberada: historico → matricula segue CASCADE,
    -- porque ali a relação É composicional (1:1, não existe sem a matrícula).
    -- O RESTRICT aqui barra a cadeia na origem.
    ADD CONSTRAINT fk_matricula_aluno
        FOREIGN KEY (id_aluno) REFERENCES aluno (id_aluno)
        ON DELETE RESTRICT ON UPDATE CASCADE;


ALTER TABLE matricula
    ADD CONSTRAINT fk_matricula_turma
        FOREIGN KEY (id_turma) REFERENCES turma (id_turma)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- HISTORICO
-- ============================================================

ALTER TABLE historico
    ADD CONSTRAINT pk_historico PRIMARY KEY (id_historico),

    -- O U do modelo: garante o 1:1.
    ADD CONSTRAINT uq_historico_matricula UNIQUE (id_matricula),

    -- CASCADE: histórico é parte composicional da matrícula. Sem a matrícula,
    -- a linha de notas não tem sujeito.
    ADD CONSTRAINT fk_historico_matricula
        FOREIGN KEY (id_matricula) REFERENCES matricula (id_matricula)
        ON DELETE CASCADE ON UPDATE CASCADE;

-- ============================================================
-- LOG_MATRICULA
-- ============================================================

-- Sem FK — deliberado (ver comentário em 02_tabelas.sql). Só PK e os
-- CHECKs de formato do payload.

ALTER TABLE log_matricula
    ADD CONSTRAINT pk_log_matricula PRIMARY KEY (id_log_matricula),

    ADD CONSTRAINT ck_log_matricula_acao_preenchida
        CHECK (length(btrim(acao_log_matricula)) > 0),

    -- Objeto no topo do jsonb, não array nem escalar. Padroniza o consumo:
    -- quem lê o log sabe que detalhe->>'chave' sempre faz sentido.
    -- jsonb_typeof é IMMUTABLE, então serve em CHECK.
    ADD CONSTRAINT ck_log_matricula_detalhe_objeto
        CHECK (detalhe_log_matricula IS NULL OR jsonb_typeof(detalhe_log_matricula) = 'object');
