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
-- Para guardar a saída como evidência, veja evidencias/transacoes.md.
--
-- PRÉ-CONDIÇÃO
--   01_ddl.sql e 02_carga.sql já executados. A carga deixa cada turma de
--   2026/2 com vagas_turma = 41 e 40 matrículas 'ativa' (1 vaga livre).
--
-- COMO FUNCIONA
--   A sessão A é o próprio script. A sessão B é uma segunda conexão aberta
--   com dblink (extensão incluída na imagem postgres:17; o usuário bd2 é
--   superusuário). Assim a concorrência acontece num único arquivo.
--
--   Este arquivo usa só SQL, sem meta-comandos do psql (\timing, \gset) e
--   sem variáveis :x. Por isso roda também no pgAdmin.
--
--   Cada cenário apaga as matrículas de teste no fim. O script começa
--   limpando execuções anteriores, então pode ser executado mais de uma vez.
--
-- REGRA DE OCUPAÇÃO
--   Ocupa vaga: status_matricula IN ('ativa', 'concluida') (mesma regra de
--   02_carga.sql). 'trancada' e 'cancelada' liberam a vaga.
--
-- ATENÇÃO
--   Não executado no banco pelo autor. Os valores "Esperado" abaixo são
--   previsões a partir do DDL e da carga. Confira na saída.

-- ---------------------------------------------------------------------
-- 0. Preparação
-- ---------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS dblink;

-- Fecha conexão B deixada por uma execução anterior, se existir.
SELECT CASE WHEN 'conn_b' = ANY (dblink_get_connections())
            THEN dblink_disconnect('conn_b') END;

SELECT dblink_connect('conn_b',
    'dbname=matricula user=bd2 password=bd2 host=localhost port=5432');

-- Limite de espera por bloqueio nas duas sessões. Um bloqueio legítimo (B
-- esperando A no cenário 2) dura milissegundos. Um bloqueio preso por uma
-- sessão antiga vira erro 55P03 em vez de travar o script.
SET lock_timeout = '10s';
SELECT dblink_exec('conn_b', 'SET lock_timeout = ''10s''');

-- Configuração do cenário, em tabela temporária.
-- Turma: CCODM2B-BD2 (Banco de Dados II, 2026/2, matutino CCO).
-- Alunos: 202510041 e 202510042 (coorte CCONM), fora dessa turma.
-- Schema de trabalho do script. Tabelas comuns (não temporárias) para
-- não depender da sessão: se a conexão reiniciar, os dados continuam.
DROP SCHEMA IF EXISTS tx_teste CASCADE;
CREATE SCHEMA tx_teste;

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

CREATE TABLE tx_teste.marcas (
    ordem    bigserial PRIMARY KEY,
    cenario  text,
    marco    text,
    instante timestamptz NOT NULL DEFAULT clock_timestamp()
);

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
-- 1. Anomalia: disputa pela última vaga SEM proteção
-- ---------------------------------------------------------------------
-- A: BEGIN, consulta, INSERT aluno_a (sem COMMIT)
-- B: BEGIN, consulta (vê 1 vaga livre), INSERT aluno_b
-- A: COMMIT    B: COMMIT
-- Esperado: 42 matrículas para 41 vagas.

INSERT INTO tx_teste.marcas (cenario, marco) VALUES ('1-sem protecao', 'inicio');

ROLLBACK;  -- garante que não há transação aberta (aviso se não houver)
BEGIN;
SELECT 'A: ocupadas antes do INSERT' AS passo, COUNT(*) AS ocupadas
  FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND status_matricula IN ('ativa', 'concluida');
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
VALUES ((SELECT aluno_a FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg), 'ativa');

SELECT dblink_exec('conn_b', 'BEGIN');
SELECT * FROM dblink('conn_b', format(
    'SELECT count(*)::int FROM tb_matricula WHERE id_turma = %s AND status_matricula IN (''ativa'', ''concluida'')',
    (SELECT id_turma FROM tx_teste.cfg))) AS t(ocupadas int);
-- Esperado: 40 (B não vê o INSERT de A, ainda não confirmado)
SELECT dblink_exec('conn_b', format(
    'INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula) VALUES (%s, %s, ''ativa'')',
    (SELECT aluno_b FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg))) AS b_insert_status;
-- Esperado: INSERT 0 1

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
-- A: BEGIN, FOR UPDATE na turma, INSERT condicionado a vaga (sem COMMIT)
-- B: BEGIN, FOR UPDATE na mesma turma: fica BLOQUEADA
-- A: COMMIT (libera o bloqueio)
-- B: revalida a ocupação (inclui aluno_a), não insere, COMMIT
-- Esperado: 41 para 41; B registra INSERT 0 0.

INSERT INTO tx_teste.marcas (cenario, marco) VALUES ('2-FOR UPDATE', 'inicio');

ROLLBACK;  -- garante que não há transação aberta (aviso se não houver)
BEGIN;
SELECT vagas_turma FROM tb_turma WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg) FOR UPDATE;
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
SELECT (SELECT aluno_a FROM tx_teste.cfg), (SELECT id_turma FROM tx_teste.cfg), 'ativa'
 WHERE (SELECT COUNT(*) FROM tb_matricula
         WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
           AND status_matricula IN ('ativa', 'concluida'))
       < (SELECT vagas_turma FROM tb_turma WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg));
-- Esperado: INSERT 0 1

SELECT dblink_exec('conn_b', 'BEGIN');
SELECT dblink_send_query('conn_b', format(
    'SELECT vagas_turma FROM tb_turma WHERE id_turma = %s FOR UPDATE',
    (SELECT id_turma FROM tx_teste.cfg)));

SELECT pg_sleep(1);
SELECT dblink_is_busy('conn_b') AS b_bloqueada;
-- Esperado: 1 (B aguarda o bloqueio de A)

SELECT pid, wait_event_type, wait_event
  FROM pg_stat_activity
 WHERE datname = current_database()
   AND wait_event_type = 'Lock';
-- Esperado: uma linha, a sessão B em Lock

COMMIT;

-- Lê o resultado do SELECT ... FOR UPDATE de B...
SELECT * FROM dblink_get_result('conn_b') AS t(vagas int);
-- ...e consome o marcador de fim, senão a conexão fica ocupada e o próximo
-- dblink_exec falha com "another command is already in progress".
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
-- Esperado: INSERT 0 0

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
-- 3. Correção 2: SERIALIZABLE com retentativa
-- ---------------------------------------------------------------------
-- A: BEGIN SERIALIZABLE, consulta, INSERT condicionado a vaga (sem COMMIT)
-- B: BEGIN SERIALIZABLE, consulta, INSERT condicionado a vaga (sem COMMIT)
-- A: COMMIT (confirma primeiro)
-- B: COMMIT tenta confirmar; se o SSI aborta, SQLSTATE 40001 e a transação
--    inteira é refeita (até 3 tentativas). Na nova tentativa a turma está
--    cheia e nada é inserido.
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

-- B: tentativa 1 é o COMMIT da transação já aberta acima; as seguintes
-- refazem a transação inteira. Erros 40001 são capturados e registrados.
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
-- 4. Comparação e conferência
-- ---------------------------------------------------------------------

-- Resultados registrados durante a execução.
SELECT cenario, passo, resultado
  FROM tx_teste.resultados
 ORDER BY ordem;

-- Custo: duração de cada cenário em milissegundos.
SELECT i.cenario,
       round((extract(epoch FROM (f.instante - i.instante)) * 1000)::numeric, 1) AS duracao_ms
  FROM tx_teste.marcas i
  JOIN tx_teste.marcas f
    ON f.cenario = i.cenario
   AND i.marco = 'inicio'
   AND f.marco = 'fim'
 ORDER BY i.ordem;

-- Conferência: nenhuma matrícula de teste deve restar.
SELECT COUNT(*) AS matriculas_de_teste_restantes
  FROM tb_matricula
 WHERE id_turma = (SELECT id_turma FROM tx_teste.cfg)
   AND id_aluno IN (SELECT aluno_a FROM tx_teste.cfg UNION SELECT aluno_b FROM tx_teste.cfg);
-- Esperado: 0

SELECT dblink_disconnect('conn_b');

-- O schema tx_teste (cfg, resultados, marcas) é mantido após a execução para
-- que scripts/evidencias_transacoes.sh gere o relatório. A próxima execução
-- recria o schema do zero.