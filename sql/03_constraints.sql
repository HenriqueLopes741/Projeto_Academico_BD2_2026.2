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

-- ============================================================
-- PROFESSOR
-- ============================================================

ALTER TABLE professor
    -- Identificador único do professor.
    ADD CONSTRAINT pk_professor PRIMARY KEY (id),

    -- Não permite dois professores com a mesma matrícula.
    ADD CONSTRAINT uq_professor_matricula UNIQUE (matricula),

    -- Não permite dois professores com o mesmo email.
    ADD CONSTRAINT uq_professor_email UNIQUE (email),

    -- Impede matrícula vazia ou apenas com espaços.
    ADD CONSTRAINT ck_professor_matricula_preenchida
        CHECK (length(btrim(matricula)) > 0),

    -- Impede nome vazio ou apenas com espaços.
    ADD CONSTRAINT ck_professor_nome_preenchido
        CHECK (length(btrim(nome)) > 0),

    -- Obriga o email a ser armazenado em letras minúsculas.
    -- Ex.: joao@email.com é válido; Joao@email.com não.
    ADD CONSTRAINT ck_professor_email_minusculo
        CHECK (email = lower(email)),

    -- Validação básica do formato do email.
    -- Não é uma validação completa de RFC.
    ADD CONSTRAINT ck_professor_email_formato
        CHECK (email LIKE '%_@_%._%');

-- ============================================================
-- CURSO
-- ============================================================

ALTER TABLE curso
    -- Identifica unicamente cada curso.
    ADD CONSTRAINT pk_curso PRIMARY KEY (id),

    -- Não permite dois cursos com o mesmo código.
    ADD CONSTRAINT uq_curso_codigo UNIQUE (codigo),

    -- Impede código vazio ou apenas com espaços.
    ADD CONSTRAINT ck_curso_codigo_preenchido
        CHECK (length(btrim(codigo)) > 0),

    -- Impede nome vazio ou apenas com espaços.
    ADD CONSTRAINT ck_curso_nome_preenchido
        CHECK (length(btrim(nome)) > 0),

    -- Garante que a carga horária seja maior que zero.
    ADD CONSTRAINT ck_curso_ch_total_positiva
        CHECK (ch_total > 0),

    -- Relaciona o curso ao campus.
    -- RESTRICT impede apagar um campus que ainda possui cursos.
    -- CASCADE atualiza campus_id caso o id do campus seja alterado.
    ADD CONSTRAINT fk_curso_campus
        FOREIGN KEY (campus_id) REFERENCES campus (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- SALA
-- ============================================================

ALTER TABLE sala
    -- Identifica unicamente cada sala.
    ADD CONSTRAINT pk_sala PRIMARY KEY (id),

    -- Garante que o código seja único dentro de cada campus.
    -- O mesmo código pode existir em campi diferentes.
    -- Ex.: Campus 1 → A-101 | Campus 2 → A-101.
    ADD CONSTRAINT uq_sala_campus_codigo
        UNIQUE (campus_id, codigo),

    -- Impede código vazio ou apenas com espaços.
    ADD CONSTRAINT ck_sala_codigo_preenchido
        CHECK (length(btrim(codigo)) > 0),

    -- Garante uma capacidade entre 1 e 1000 pessoas.
    -- Evita valores inválidos ou possíveis erros de digitação.
    ADD CONSTRAINT ck_sala_capacidade
        CHECK (capacidade BETWEEN 1 AND 1000),

    -- Relaciona a sala ao campus.
    -- RESTRICT impede apagar um campus que ainda possui salas.
    -- CASCADE atualiza campus_id caso o id do campus seja alterado.
    ADD CONSTRAINT fk_sala_campus
        FOREIGN KEY (campus_id) REFERENCES campus (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- FERIADO
-- ============================================================

ALTER TABLE feriado
    -- Identifica unicamente cada feriado.
    ADD CONSTRAINT pk_feriado PRIMARY KEY (id),

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
        UNIQUE NULLS NOT DISTINCT (data, campus_id),

    -- Impede descrição vazia ou formada apenas por espaços.
    ADD CONSTRAINT ck_feriado_descricao_preenchida
        CHECK (length(btrim(descricao)) > 0),

    -- Relaciona o feriado ao campus.
    -- Quando campus_id estiver preenchido, ele precisa existir
    -- em campus.id.
    -- RESTRICT impede apagar um campus que possui feriados locais.
    -- CASCADE atualiza campus_id caso o id do campus seja alterado.
    ADD CONSTRAINT fk_feriado_campus
        FOREIGN KEY (campus_id) REFERENCES campus (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- PRE_REQUISITO
-- ============================================================

ALTER TABLE pre_requisito
    -- Chave primária composta pelo par de disciplinas.
    -- Impede que o mesmo relacionamento seja cadastrado duas vezes.
    -- Não é necessário criar um id separado.
    ADD CONSTRAINT pk_pre_requisito
        PRIMARY KEY (disciplina_id, requisito_id),

    -- Impede que uma disciplina seja requisito dela mesma.
    -- Ex.: Algoritmos I não pode exigir Algoritmos I.
    -- Não impede ciclos maiores, como A → B → A.
    ADD CONSTRAINT ck_pre_requisito_sem_autorreferencia
        CHECK (disciplina_id <> requisito_id),

    -- Garante que a disciplina que possui o requisito exista.
    -- CASCADE: ao apagar essa disciplina, seus vínculos de
    -- pré-requisito também são removidos.
    ADD CONSTRAINT fk_pre_requisito_disciplina
        FOREIGN KEY (disciplina_id) REFERENCES disciplina (id)
        ON DELETE CASCADE ON UPDATE CASCADE,

    -- Garante que a disciplina exigida exista.
    -- RESTRICT: impede apagar uma disciplina que ainda é
    -- utilizada como requisito por outra.
    ADD CONSTRAINT fk_pre_requisito_requisito
        FOREIGN KEY (requisito_id) REFERENCES disciplina (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- TURMA
-- ============================================================

ALTER TABLE turma
    -- Identifica cada turma de forma única.
    ADD CONSTRAINT pk_turma PRIMARY KEY (id),

    -- O código pode se repetir em períodos diferentes,
    -- mas não pode se repetir dentro do mesmo período.
    -- Ex.: CCODM2B pode existir em 2026/1 e 2026/2.
    ADD CONSTRAINT uq_turma_periodo_codigo
        UNIQUE (periodo_letivo_id, codigo),

    -- Impede código vazio ou formado apenas por espaços.
    ADD CONSTRAINT ck_turma_codigo_preenchido
        CHECK (length(btrim(codigo)) > 0),

    -- Garante pelo menos 1 vaga e limita a 300.
    ADD CONSTRAINT ck_turma_vagas
        CHECK (vagas BETWEEN 1 AND 300),

    -- Relaciona a turma à disciplina.
    -- RESTRICT impede apagar uma disciplina que possui turmas.
    ADD CONSTRAINT fk_turma_disciplina
        FOREIGN KEY (disciplina_id) REFERENCES disciplina (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    -- Relaciona a turma ao período letivo.
    -- RESTRICT impede apagar um período que possui turmas.
    ADD CONSTRAINT fk_turma_periodo_letivo
        FOREIGN KEY (periodo_letivo_id) REFERENCES periodo_letivo (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    -- Relaciona a turma ao professor responsável.
    -- RESTRICT impede apagar um professor que possui turmas.
    ADD CONSTRAINT fk_turma_professor
        FOREIGN KEY (professor_id) REFERENCES professor (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- CURRICULO
-- ============================================================

ALTER TABLE curriculo
    -- Identifica cada currículo de forma única.
    ADD CONSTRAINT pk_curriculo PRIMARY KEY (id),

    -- Um curso não pode possuir duas grades para o mesmo
    -- ano de vigência.
    ADD CONSTRAINT uq_curriculo_curso_ano
        UNIQUE (curso_id, ano_vigencia),

    -- Permite que (id, curso_id) seja utilizado como alvo
    -- de uma FK composta na tabela aluno.
    ADD CONSTRAINT uq_curriculo_id_curso
        UNIQUE (id, curso_id),

    -- Limita o ano de vigência ao intervalo de 2000 a 2100.
    ADD CONSTRAINT ck_curriculo_ano_vigencia
        CHECK (ano_vigencia BETWEEN 2000 AND 2100),

    -- Relaciona o currículo ao curso.
    -- RESTRICT impede apagar um curso que possui currículos.
    ADD CONSTRAINT fk_curriculo_curso
        FOREIGN KEY (curso_id) REFERENCES curso (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

COMMENT ON CONSTRAINT uq_curriculo_id_curso ON curriculo IS
    'Aparentemente redundante (id já é PK). Existe para servir de alvo à FK '
    'composta (curriculo_id, curso_id) de aluno, que garante coerência entre '
    'o curso do aluno e o curso do seu currículo. A ordem das colunas na FK '
    'precisa casar com a ordem desta UNIQUE (id, curso_id).';

-- ============================================================
-- TURMA_HORARIO
-- ============================================================

ALTER TABLE turma_horario
    -- Identifica cada horário de forma única.
    ADD CONSTRAINT pk_turma_horario PRIMARY KEY (id),

    -- Garante que o dia da semana esteja entre 1 e 7.
    ADD CONSTRAINT ck_turma_horario_dia_semana
        CHECK (dia_semana BETWEEN 1 AND 7),

    -- Garante que a faixa possua início e fim e não seja vazia.
    ADD CONSTRAINT ck_turma_horario_faixa_valida
        CHECK (NOT isempty(faixa)
        AND lower(faixa) IS NOT NULL
        AND upper(faixa) IS NOT NULL),

    -- Impede duas turmas na mesma sala, no mesmo dia,
    -- com horários sobrepostos.
    -- Utiliza btree_gist para permitir '=' em sala_id e dia_semana.
    ADD CONSTRAINT ex_turma_horario_sala_ocupada
        EXCLUDE USING gist (
            sala_id WITH =,
            dia_semana WITH =,
            faixa WITH &&
        ),

    -- Relaciona o horário à turma.
    -- CASCADE exclui os horários quando a turma é excluída.
    ADD CONSTRAINT fk_turma_horario_turma
        FOREIGN KEY (turma_id) REFERENCES turma (id)
        ON DELETE CASCADE ON UPDATE CASCADE,

    -- Relaciona o horário à sala.
    -- RESTRICT impede apagar uma sala que possui horários.
    ADD CONSTRAINT fk_turma_horario_sala
        FOREIGN KEY (sala_id) REFERENCES sala (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

COMMENT ON CONSTRAINT ex_turma_horario_sala_ocupada ON turma_horario IS
    'Escopo: sala + dia + faixa horária. LIMITE CONHECIDO E DELIBERADO: não '
    'inclui periodo_letivo_id, que vive em turma e é inalcançável — EXCLUDE, '
    'como CHECK, só enxerga colunas da própria linha. Com carga de um único '
    'período o comportamento é correto; com múltiplos períodos bloquearia o '
    'reuso legítimo da mesma sala e horário entre semestres. Incluir exigiria '
    'denormalizar periodo_letivo_id nesta tabela (alteraria o modelo) ou uma '
    'trigger com join em turma. Também não cobre conflito de professor nem '
    'a mesma turma com horários sobrepostos em salas diferentes.';

-- ============================================================
-- CURRICULO_DISCIPLINA
-- ============================================================

ALTER TABLE curriculo_disciplina
    -- PK composta é a própria unicidade: uma disciplina aparece no máximo
    -- uma vez por currículo. Sem surrogate — o modelo não dá, e o par já
    -- identifica a linha.
    ADD CONSTRAINT pk_curriculo_disciplina
        PRIMARY KEY (curriculo_id, disciplina_id),

    -- Grade de graduação vai até ~10 períodos. Teto folgado, piso rígido:
    -- período 0 ou negativo não existe.
    ADD CONSTRAINT ck_curriculo_disciplina_periodo
        CHECK (periodo BETWEEN 1 AND 20),

    -- CASCADE: a linha é parte composicional do currículo. Apagar a grade
    -- apaga sua composição, que não significa nada isolada.
    ADD CONSTRAINT fk_curriculo_disciplina_curriculo
        FOREIGN KEY (curriculo_id) REFERENCES curriculo (id)
        ON DELETE CASCADE ON UPDATE CASCADE,

    -- RESTRICT: disciplina é catálogo independente, compartilhado por várias
    -- grades. Apagá-la esvaziaria currículos silenciosamente.
    -- Mesma assimetria de pre_requisito: composição em cascata, catálogo restrito.
    ADD CONSTRAINT fk_curriculo_disciplina_disciplina
        FOREIGN KEY (disciplina_id) REFERENCES disciplina (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- ALUNO
-- ============================================================

ALTER TABLE aluno
    -- Identifica cada aluno de forma única.
    ADD CONSTRAINT pk_aluno PRIMARY KEY (id),

    -- Não permite dois alunos com a mesma matrícula.
    ADD CONSTRAINT uq_aluno_matricula UNIQUE (matricula),

    -- Não permite dois alunos com o mesmo CPF.
    ADD CONSTRAINT uq_aluno_cpf UNIQUE (cpf),

    -- Não permite dois alunos com o mesmo email.
    ADD CONSTRAINT uq_aluno_email UNIQUE (email),

    -- Impede matrícula vazia ou apenas com espaços.
    ADD CONSTRAINT ck_aluno_matricula_preenchida
        CHECK (length(btrim(matricula)) > 0),

    -- Impede nome vazio ou apenas com espaços.
    ADD CONSTRAINT ck_aluno_nome_preenchido
        CHECK (length(btrim(nome)) > 0),

    -- Único CHECK de formato do projeto, e a exceção se justifica: CPF tem
    -- formato universalmente fixo (11 dígitos), ao contrário de codigo/
    -- matricula, onde regex quebraria a carga real. Não valida dígito
    -- verificador — isso é regra de aplicação, não de integridade estrutural.
    ADD CONSTRAINT ck_aluno_cpf_valido
        CHECK (cpf ~ '^[0-9]{11}$'),

    -- Mesma política de professor: normaliza em vez de índice funcional.
    ADD CONSTRAINT ck_aluno_email_minusculo
        CHECK (email = lower(email)),
    ADD CONSTRAINT ck_aluno_email_formato
        CHECK (email LIKE '%_@_%._%'),

    -- CHECKs multi-coluna: enxergam a linha inteira.
    ADD CONSTRAINT ck_aluno_ingresso_apos_nascimento
        CHECK (ingresso > nascimento),

    -- Piso defensivo contra digitação (1900) sem inventar idade mínima.
    ADD CONSTRAINT ck_aluno_nascimento_plausivel
        CHECK (nascimento BETWEEN '1900-01-01' AND current_date),

    -- FK COMPOSTA — o ponto da tabela.
    -- As duas colunas isoladas seriam válidas independentemente: nada
    -- impediria aluno no curso de Computação com currículo de Direito.
    -- Esta FK exige que o PAR exista junto em curriculo, o que só é
    -- verdade se o currículo pertencer àquele curso.
    -- Só é declarável porque curriculo tem uq_curriculo_id_curso: FK exige
    -- PK ou UNIQUE cobrindo as colunas referenciadas.
    -- Substitui a FK simples para curriculo — declarar as duas seria redundante.
    ADD CONSTRAINT fk_aluno_curriculo_curso
        FOREIGN KEY (curriculo_id, curso_id) REFERENCES curriculo (id, curso_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    -- FK simples para curso: NÃO é redundante com a composta. A composta
    -- garante coerência do par; esta garante que curso_id aponta para curso
    -- existente mesmo isoladamente, e é o que o modelo declara.
    ADD CONSTRAINT fk_aluno_curso
        FOREIGN KEY (curso_id) REFERENCES curso (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

COMMENT ON CONSTRAINT fk_aluno_curriculo_curso ON aluno IS
    'Depende de uq_curriculo_id_curso em curriculo. Se aquela UNIQUE for '
    'removida, esta FK deixa de ser declarável.';

-- ============================================================
-- MATRICULA
-- ============================================================

ALTER TABLE matricula
    -- Identifica cada matrícula de forma única.
    ADD CONSTRAINT pk_matricula PRIMARY KEY (id),

    -- Impede que um mesmo aluno se matricule duas vezes na mesma turma.
    ADD CONSTRAINT uq_matricula_aluno_turma
        UNIQUE (aluno_id, turma_id),

    -- Matrícula com data futura é erro de carga ou de relógio.
    ADD CONSTRAINT ck_matricula_data_nao_futura
        CHECK (data_matricula <= now()),



    -- RESTRICT: matrícula NÃO é parte composicional do aluno — é registro
    -- acadêmico com valor próprio, que a instituição precisa preservar mesmo
    -- após o desligamento. Com CASCADE, apagar um aluno propagaria por
    -- matricula até historico (também CASCADE), destruindo notas e frequência
    -- em silêncio. Desligamento é ativo = false, nunca DELETE — e é por isso
    -- que a coluna aluno.ativo existe no modelo.
    -- Note a assimetria deliberada: historico → matricula segue CASCADE,
    -- porque ali a relação É composicional (1:1, não existe sem a matrícula).
    -- O RESTRICT aqui barra a cadeia na origem.
    ADD CONSTRAINT fk_matricula_aluno
        FOREIGN KEY (aluno_id) REFERENCES aluno (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;


ALTER TABLE matricula
    ADD CONSTRAINT fk_matricula_turma
        FOREIGN KEY (turma_id) REFERENCES turma (id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

-- ============================================================
-- HISTORICO
-- ============================================================

ALTER TABLE historico
    ADD CONSTRAINT pk_historico PRIMARY KEY (id),

    -- O U do modelo: garante o 1:1.
    ADD CONSTRAINT uq_historico_matricula UNIQUE (matricula_id),

    -- CASCADE: histórico é parte composicional da matrícula. Sem a matrícula,
    -- a linha de notas não tem sujeito.
    ADD CONSTRAINT fk_historico_matricula
        FOREIGN KEY (matricula_id) REFERENCES matricula (id)
        ON DELETE CASCADE ON UPDATE CASCADE;

-- ============================================================
-- LOG_MATRICULA
-- ============================================================

-- Sem FK — deliberado (ver comentário em 02_tabelas.sql). Só PK e os
-- CHECKs de formato do payload.

ALTER TABLE log_matricula
    ADD CONSTRAINT pk_log_matricula PRIMARY KEY (id),

    ADD CONSTRAINT ck_log_matricula_acao_preenchida
        CHECK (length(btrim(acao)) > 0),

    -- Objeto no topo do jsonb, não array nem escalar. Padroniza o consumo:
    -- quem lê o log sabe que detalhe->>'chave' sempre faz sentido.
    -- jsonb_typeof é IMMUTABLE, então serve em CHECK.
    ADD CONSTRAINT ck_log_matricula_detalhe_objeto
        CHECK (detalhe IS NULL OR jsonb_typeof(detalhe) = 'object');
