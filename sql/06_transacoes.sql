-- =====================================================================
-- 06_transacoes.sql
-- Anomalia de concorrência (disputa pela última vaga) + 2 correções
-- Frente: Transações e Concorrência
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================
--
-- EXECUÇÃO (conforme EXECUTE.md)
--   docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/06_transacoes.sql
--
-- Para gerar o relatório com os dados da execução:
--   bash scripts/evidencias_transacoes.sh
--
-- PRÉ-CONDIÇÃO
--   01_ddl.sql e 02_carga.sql já executados. A carga deixa cada turma de
--   2026/2 com vagas_turma = 41 e 40 matrículas 'ativa' (1 vaga livre).
--
-- COMO FUNCIONA
--   A sessão A é o próprio script. A sessão B é uma segunda conexão aberta
--   com dblink (extensão incluída na imagem postgres:17; o usuário bd2 é
--   superusuário). A concorrência acontece num único arquivo, sem sessões
--   manuais.
--
--   Só SQL, sem meta-comandos do psql e sem variáveis :x. Roda pelo stdin,
--   por psql -f e pelo pgAdmin.
--
--   Os dados do cenário ficam no schema tx_teste (tabelas comuns, não
--   temporárias, para não depender da sessão). O schema é recriado a cada
--   execução e mantido ao final para o gerador de evidências.
--
-- NÍVEIS DE ISOLAMENTO
--   Cenários 1 e 2: READ COMMITTED (explícito).
--   Cenário 3: SERIALIZABLE.
--   O porquê de cada escolha está documentado em evidencias/transacoes.md.
--
-- PERMISSÕES
--   SELECT ... FOR UPDATE exige privilégio UPDATE em tb_turma. O script roda
--   como bd2 (dono do banco), então funciona localmente. O role usado pela
--   aplicação de matrículas (definido em 07_seguranca_rls.sql) precisa de
--   GRANT UPDATE ON tb_turma.
--
-- REGRA DE OCUPAÇÃO
--   Ocupa vaga: status_matricula IN ('ativa', 'concluida') (mesma regra de
--   02_carga.sql). 'trancada' e 'cancelada' liberam a vaga.

-- ---------------------------------------------------------------------
-- 0. Preparação
-- ---------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS dblink;

-- Fecha conexão B deixada por uma execução anterior, se existir.
SELECT CASE WHEN 'conn_b' = ANY (dblink_get_connections())
            THEN dblink_disconnect('conn_b') END;

SELECT dblink_connect('conn_b',
    'dbname=matricula user=bd2 password=bd2 host=localhost port=5432');

-- Limite de espera por bloqueio nas duas sessões: um bloqueio preso vira
-- erro 55P03 em vez de travar o script.
SET lock_timeout = '10s';
SELECT dblink_exec('conn_b', 'SET lock_timeout = ''10s''');

-- Schema de trabalho, recriado a cada execução.
DROP SCHEMA IF EXISTS tx_teste CASCADE;
CREATE SCHEMA tx_teste;

-- Configuração do cenário.
-- Turma: CCODM2B-BD2 (Banco de Dados II, 2026/2, matutino CCO).
-- Alunos: 202510041 e 202510042 (coorte CCONM), fora dessa turma.
CREATE TABLE tx_teste.cfg AS
SELECT t.id_turma,
       a.id_aluno AS aluno_a,
       b.id_aluno AS aluno_b
  FROM tb_turma t
  JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
  CROSS JOIN tb_aluno a
  CROSS JOIN tb_aluno b
 WHERE t.codigo_turma = 'CCODM2B-BD2'
   AND pl.ano_periodo_letivo = 2026
   AND pl.semestre_periodo_letivo = 2
   AND a.matricula_aluno = '202510041'
   AND b.matricula_aluno = '202510042';

CREATE TABLE tx_teste.resultados (
    ordem     bigserial PRIMARY KEY,
    cenario   text,
    passo     text,
    resultado text
);

-- Marcas de tempo (clock_timestamp mede o instante real, não o início da transação).
CREATE TABLE tx_teste.marcas (
    ordem    bigserial PRIMARY KEY,
    cenario  text,
    marco    text,
    instante timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- PIDs das duas sessões. pid_a é o script; pid_b é a conexão dblink. A
-- verificação de bloqueio usa pid_b, para provar que B (e não outra sessão)
-- está esperando o bloqueio de A.
CREATE TABLE tx_teste.sessoes AS
SELECT pg_backend_pid() AS pid_a,
       (SELECT t.pid FROM dblink('conn_b', 'SELECT pg_backend_pid()') AS t(pid int)) AS pid_b;

-- Limpeza de execuções anteriores.
DELETE FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND id_aluno IN (SELECT aluno_a FROM tx_teste.cfg UNION SELECT aluno_b FROM tx_teste.cfg);

-- Estado inicial. Esperado: vagas_livres = 1.
SELECT '0. estado inicial' AS passo,
       t.vagas_turma,
       COUNT(m.id_matricula) FILTER (WHERE m.status_matricula IN ('ativa', 'concluida')) AS ocupadas,
       t.vagas_turma - COUNT(m.id_matricula) FILTER (WHERE m.status_matricula IN ('ativa', 'concluida')) AS vagas_livres
  FROM tb_turma t
  LEFT JOIN tb_matricula m ON m.id_turma = t.id_turma
 WHERE t.id_turma = (SELECT id_turma FROM tx_teste.cfg)
 GROUP BY t.vagas_turma;

-- ---------------------------------------------------------------------
-- 1. Anomalia: disputa pela última vaga SEM bloqueio
-- ---------------------------------------------------------------------
-- Ambas as transações verificam a vaga com o mesmo INSERT ... WHERE
-- count < vagas, mas sem lock. Cada uma lê 40 ocupadas e passa na verificação.
-- Como nenhuma enxerga a inserção da outra (ainda não confirmada), as duas
-- inserem. Esperado: 42 matrículas para 41 vagas.
--
-- A: BEGIN READ COMMITTED, consulta, INSERT condicionado (sem COMMIT)
-- B: BEGIN READ COMMITTED, consulta (vê 40), INSERT condicionado (vê 40 < 41)
-- A: COMMIT
-- B: COMMIT

INSERT INTO tx_teste.marcas (cenario, marco) VALUES ('1-sem protecao', 'inicio');

ROLLBACK;  -- garante que não há transação aberta (aviso se não houver)
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT 'A: ocupadas antes do INSERT' AS passo, COUNT(*) AS ocupadas
  FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND status_matricula IN ('ativa', 'concluida');
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
SELECT (SELECT aluno_a FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg), 'ativa'
 WHERE (SELECT COUNT(*) FROM tb_matricula
         WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
           AND status_matricula IN ('ativa', 'concluida'))
       < (SELECT vagas_turma FROM tb_turma WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg));
-- Esperado: INSERT 0 1 (A vê 40 < 41)

SELECT dblink_exec('conn_b', 'BEGIN ISOLATION LEVEL READ COMMITTED');
SELECT * FROM dblink('conn_b', format(
    'SELECT count(*)::int FROM tb_matricula WHERE id_turma = %s AND status_matricula IN (''ativa'', ''concluida'')',
    (SELECT id_turma FROM tx_teste.cfg))) AS t(ocupadas int);
-- Esperado: 40 (A ainda não confirmou)
SELECT dblink_exec('conn_b', format(
    'INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
     SELECT %s, %s, ''ativa''
      WHERE (SELECT COUNT(*) FROM tb_matricula
              WHERE id_turma = %s AND status_matricula IN (''ativa'', ''concluida''))
            < (SELECT vagas_turma FROM tb_turma WHERE id_turma = %s)',
    (SELECT aluno_b FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg),
    (SELECT id_turma FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg))) AS b_insert_status;
-- Esperado: INSERT 0 1 (B também vê 40 < 41)

COMMIT;
SELECT dblink_exec('conn_b', 'COMMIT') AS b_commit_status;

INSERT INTO tx_teste.marcas (cenario, marco) VALUES ('1-sem protecao', 'fim');

SELECT '1. anomalia: matriculas x vagas' AS passo,
       t.vagas_turma,
       COUNT(m.id_matricula) AS matriculas_ocupando_vaga
  FROM tb_turma t
  LEFT JOIN tb_matricula m
         ON m.id_turma = t.id_turma
        AND m.status_matricula IN ('ativa', 'concluida')
 WHERE t.id_turma = (SELECT id_turma FROM tx_teste.cfg)
 GROUP BY t.vagas_turma;
-- Esperado: 42 > 41

INSERT INTO tx_teste.resultados (cenario, passo, resultado)
SELECT '1-sem protecao', 'overbooking',
       'matriculas ' || COUNT(*) || ' para vagas 41'
  FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND status_matricula IN ('ativa', 'concluida');

DELETE FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND id_aluno IN (SELECT aluno_a FROM tx_teste.cfg UNION SELECT aluno_b FROM tx_teste.cfg);

-- ---------------------------------------------------------------------
-- 2. Correção 1: bloqueio explícito (SELECT ... FOR UPDATE)
-- ---------------------------------------------------------------------
-- A: BEGIN READ COMMITTED, FOR UPDATE na turma, INSERT condicionado (sem COMMIT)
-- B: BEGIN READ COMMITTED, FOR UPDATE na mesma turma: fica BLOQUEADA
-- A: COMMIT (libera o bloqueio)
-- B: obtém o bloqueio, o INSERT condicionado vê 41 ocupadas e não insere
-- B: COMMIT
--
-- A espera de B é medida: instante do envio de B até o COMMIT de A.
-- Nenhum pg_sleep: um loop verifica se B está bloqueada antes de A confirmar.
-- Esperado: 41 para 41; B registra INSERT 0 0.

INSERT INTO tx_teste.marcas (cenario, marco) VALUES ('2-FOR UPDATE', 'inicio');

ROLLBACK;  -- garante que não há transação aberta (aviso se não houver)
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT vagas_turma FROM tb_turma WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg) FOR UPDATE;
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
SELECT (SELECT aluno_a FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg), 'ativa'
 WHERE (SELECT COUNT(*) FROM tb_matricula
         WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
           AND status_matricula IN ('ativa', 'concluida'))
       < (SELECT vagas_turma FROM tb_turma WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg));
-- Esperado: INSERT 0 1

SELECT dblink_exec('conn_b', 'BEGIN ISOLATION LEVEL READ COMMITTED');

INSERT INTO tx_teste.marcas (cenario, marco) VALUES ('2-FOR UPDATE', 'b_envia');
SELECT dblink_send_query('conn_b', format(
    'SELECT vagas_turma FROM tb_turma WHERE id_turma = %s FOR UPDATE',
    (SELECT id_turma FROM tx_teste.cfg)));

-- Espera até que o PostgreSQL confirme que B está bloqueada por A (limite de
-- ~2 s). dblink_is_busy não basta: ele vira 1 assim que a consulta é enviada,
-- mesmo antes de B chegar ao bloqueio. pg_blocking_pids indica quem bloqueia
-- cada sessão. Se B não ficar bloqueada, o teste não é válido e o script para.
DO $$
DECLARE
    i         int     := 0;
    bloqueada boolean := false;
BEGIN
    WHILE NOT bloqueada LOOP
        i := i + 1;
        IF i > 200 THEN
            RAISE EXCEPTION 'B não ficou bloqueada pelo FOR UPDATE de A';
        END IF;

        SELECT EXISTS (
            SELECT 1
              FROM pg_stat_activity p
              JOIN tx_teste.sessoes s ON p.pid = s.pid_b
             WHERE p.datname = current_database()
               AND p.wait_event_type = 'Lock'
               AND pg_blocking_pids(p.pid) @> ARRAY[s.pid_a]
        ) INTO bloqueada;

        IF NOT bloqueada THEN
            PERFORM pg_sleep(0.01);
        END IF;
    END LOOP;
END
$$;

SELECT p.pid AS pid_b, p.wait_event_type, p.wait_event,
       pg_blocking_pids(p.pid) AS bloqueada_por
  FROM pg_stat_activity p
  JOIN tx_teste.sessoes s ON p.pid = s.pid_b;
-- Esperado: uma linha, pid_b em Lock (transactionid), bloqueada_por = {pid_a}

INSERT INTO tx_teste.marcas (cenario, marco) VALUES ('2-FOR UPDATE', 'a_commit');
COMMIT;

-- B obtém o bloqueio, conclui o SELECT e revalida.
SELECT * FROM dblink_get_result('conn_b') AS t(vagas int);
-- Consome o marcador de fim do resultado assíncrono; senão a conexão fica
-- ocupada e o próximo dblink_exec falha com "another command is already in progress".
SELECT count(*) AS drenagem_b FROM dblink_get_result('conn_b') AS t(vagas int);
-- Esperado: 0

SELECT dblink_exec('conn_b', format(
    'INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
     SELECT %s, %s, ''ativa''
      WHERE (SELECT COUNT(*) FROM tb_matricula
              WHERE id_turma = %s AND status_matricula IN (''ativa'', ''concluida''))
            < (SELECT vagas_turma FROM tb_turma WHERE id_turma = %s)',
    (SELECT aluno_b FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg),
    (SELECT id_turma FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg))) AS b_insert_status;
-- Esperado: INSERT 0 0 (B vê 41 ocupadas, após o COMMIT de A)

SELECT dblink_exec('conn_b', 'COMMIT');

INSERT INTO tx_teste.marcas (cenario, marco) VALUES ('2-FOR UPDATE', 'fim');

SELECT '2. FOR UPDATE: matriculas x vagas' AS passo,
       t.vagas_turma,
       COUNT(m.id_matricula) AS matriculas_ocupando_vaga
  FROM tb_turma t
  LEFT JOIN tb_matricula m
         ON m.id_turma = t.id_turma
        AND m.status_matricula IN ('ativa', 'concluida')
 WHERE t.id_turma = (SELECT id_turma FROM tx_teste.cfg)
 GROUP BY t.vagas_turma;
-- Esperado: 41 = 41

INSERT INTO tx_teste.resultados (cenario, passo, resultado)
SELECT '2-FOR UPDATE', 'B espera A e nao insere',
       'matriculas ' || COUNT(*) || ' para vagas 41'
  FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND status_matricula IN ('ativa', 'concluida');

DELETE FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND id_aluno IN (SELECT aluno_a FROM tx_teste.cfg UNION SELECT aluno_b FROM tx_teste.cfg);

-- ---------------------------------------------------------------------
-- 3. Correção 2: nível de isolamento SERIALIZABLE, com retentativa
-- ---------------------------------------------------------------------
-- A: BEGIN SERIALIZABLE, consulta, INSERT condicionado (sem COMMIT)
-- B: BEGIN SERIALIZABLE, consulta, INSERT condicionado (sem COMMIT)
-- A: COMMIT (confirma primeiro)
-- B: COMMIT é abortado com SQLSTATE 40001. A transação de B é refeita
--    (até 3 tentativas). Na nova tentativa a turma está cheia e nada é inserido.
-- Esperado: 41 para 41; uma tentativa de B abortada com 40001.

INSERT INTO tx_teste.marcas (cenario, marco) VALUES ('3-SERIALIZABLE', 'inicio');

ROLLBACK;  -- garante que não há transação aberta (aviso se não houver)
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) AS ocupadas_a
  FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND status_matricula IN ('ativa', 'concluida');
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
SELECT (SELECT aluno_a FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg), 'ativa'
 WHERE (SELECT COUNT(*) FROM tb_matricula
         WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
           AND status_matricula IN ('ativa', 'concluida'))
       < (SELECT vagas_turma FROM tb_turma WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg));
-- Esperado: INSERT 0 1

SELECT dblink_exec('conn_b', 'BEGIN ISOLATION LEVEL SERIALIZABLE');
SELECT * FROM dblink('conn_b', format(
    'SELECT count(*)::int FROM tb_matricula WHERE id_turma = %s AND status_matricula IN (''ativa'', ''concluida'')',
    (SELECT id_turma FROM tx_teste.cfg))) AS t(ocupadas int);
-- Esperado: 40
SELECT dblink_exec('conn_b', format(
    'INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
     SELECT %s, %s, ''ativa''
      WHERE (SELECT COUNT(*) FROM tb_matricula
              WHERE id_turma = %s AND status_matricula IN (''ativa'', ''concluida''))
            < (SELECT vagas_turma FROM tb_turma WHERE id_turma = %s)',
    (SELECT aluno_b FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg),
    (SELECT id_turma FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg))) AS b_insert_tentativa_1;
-- Esperado: INSERT 0 1 (B ainda vê 1 vaga)

COMMIT;
-- A confirmou primeiro.

-- B: tentativa 1 é o COMMIT da transação já aberta acima. As seguintes refazem
-- a transação inteira. Erros 40001 são capturados e registrados.
DO $$
DECLARE
    v    record;
    tent int     := 1;
    ok   boolean := false;
    st   text;
BEGIN
    SELECT * INTO v FROM tx_teste.cfg;

    BEGIN
        PERFORM dblink_exec('conn_b', 'COMMIT');
        ok := true;
        INSERT INTO tx_teste.resultados (cenario, passo, resultado)
            VALUES ('3-SERIALIZABLE', 'B tentativa 1', 'COMMIT ok');
    EXCEPTION WHEN SQLSTATE '40001' THEN
        INSERT INTO tx_teste.resultados (cenario, passo, resultado)
            VALUES ('3-SERIALIZABLE', 'B tentativa 1', 'abortada com 40001');
        BEGIN
            PERFORM dblink_exec('conn_b', 'ROLLBACK');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END;

    WHILE NOT ok AND tent < 3 LOOP
        tent := tent + 1;
        BEGIN
            PERFORM dblink_exec('conn_b', 'BEGIN ISOLATION LEVEL SERIALIZABLE');
            st := dblink_exec('conn_b', format(
                'INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
                 SELECT %s, %s, ''ativa''
                  WHERE (SELECT COUNT(*) FROM tb_matricula
                          WHERE id_turma = %s AND status_matricula IN (''ativa'', ''concluida''))
                        < (SELECT vagas_turma FROM tb_turma WHERE id_turma = %s)',
                v.aluno_b, v.id_turma, v.id_turma, v.id_turma));
            PERFORM dblink_exec('conn_b', 'COMMIT');
            ok := true;
            INSERT INTO tx_teste.resultados (cenario, passo, resultado)
                VALUES ('3-SERIALIZABLE', 'B tentativa ' || tent, st || ' e COMMIT ok');
        EXCEPTION WHEN SQLSTATE '40001' THEN
            INSERT INTO tx_teste.resultados (cenario, passo, resultado)
                VALUES ('3-SERIALIZABLE', 'B tentativa ' || tent, 'abortada com 40001');
            BEGIN
                PERFORM dblink_exec('conn_b', 'ROLLBACK');
            EXCEPTION WHEN OTHERS THEN
                NULL;
            END;
        END;
    END LOOP;

    RAISE NOTICE 'B: % tentativa(s), confirmada=%', tent, ok;
END
$$;

INSERT INTO tx_teste.marcas (cenario, marco) VALUES ('3-SERIALIZABLE', 'fim');

SELECT '3. SERIALIZABLE: matriculas x vagas' AS passo,
       t.vagas_turma,
       COUNT(m.id_matricula) AS matriculas_ocupando_vaga
  FROM tb_turma t
  LEFT JOIN tb_matricula m
         ON m.id_turma = t.id_turma
        AND m.status_matricula IN ('ativa', 'concluida')
 WHERE t.id_turma = (SELECT id_turma FROM tx_teste.cfg)
 GROUP BY t.vagas_turma;
-- Esperado: 41 = 41

INSERT INTO tx_teste.resultados (cenario, passo, resultado)
SELECT '3-SERIALIZABLE', 'resultado final',
       'matriculas ' || COUNT(*) || ' para vagas 41'
  FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND status_matricula IN ('ativa', 'concluida');

DELETE FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND id_aluno IN (SELECT aluno_a FROM tx_teste.cfg UNION SELECT aluno_b FROM tx_teste.cfg);

-- ---------------------------------------------------------------------
-- 4. Conferência
-- ---------------------------------------------------------------------

SELECT cenario, passo, resultado
  FROM tx_teste.resultados
 ORDER BY ordem;

SELECT i.cenario,
       round((extract(epoch FROM (f.instante - i.instante)) * 1000)::numeric, 1) AS duracao_ms
  FROM tx_teste.marcas i
  JOIN tx_teste.marcas f
    ON f.cenario = i.cenario
   AND i.marco = 'inicio'
   AND f.marco = 'fim'
 ORDER BY i.ordem;

-- Espera de B no cenário 2: do envio até o COMMIT de A.
SELECT round((extract(epoch FROM (a.instante - b.instante)) * 1000)::numeric, 1) AS espera_b_ms
  FROM tx_teste.marcas b
  JOIN tx_teste.marcas a
    ON a.cenario = '2-FOR UPDATE' AND a.marco = 'a_commit'
 WHERE b.cenario = '2-FOR UPDATE' AND b.marco = 'b_envia';

-- Nenhuma matrícula de teste pode restar.
SELECT COUNT(*) AS matriculas_de_teste_restantes
  FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND id_aluno IN (SELECT aluno_a FROM tx_teste.cfg UNION SELECT aluno_b FROM tx_teste.cfg);
-- Esperado: 0

SELECT dblink_disconnect('conn_b');

-- O schema tx_teste é mantido para scripts/evidencias_transacoes.sh.
-- A próxima execução recria o schema.