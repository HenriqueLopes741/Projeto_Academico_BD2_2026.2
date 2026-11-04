-- =====================================================================
-- 07_seguranca_rls.sql
-- Roles (aluno, secretaria, coordenacao), GRANT/REVOKE, row-level security
-- Frente: Administração e Operação
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================
-- Pré-condição: 01 a 04 rodados (usa as views de 04).
-- Rode como dono/superusuário (bd2). Roles são do CLUSTER, não da base: por
-- isso o script checa existência antes de criar (pg_roles) e um pg_dump da
-- base NÃO leva as roles junto (ver 08_backup_restore.sql).
--
-- MODELO DE ACESSO
--   Grupos (NOLOGIN, só carregam privilégios): aluno, secretaria, coordenacao.
--   Pessoas são roles de login MEMBROS do grupo:
--     aluno_<matricula>   ex.: aluno_202510007  → membro de aluno
--     sec_demo, coord_demo → membros de secretaria / coordenacao (demonstração)
--
--   Como o RLS sabe QUEM é o aluno? Pelo nome da role: current_user =
--   'aluno_' || matricula_aluno. Não usei variável de sessão (SET app.x) porque
--   o próprio aluno, com acesso ao banco, poderia trocar o valor e se passar por
--   outro. O nome da role não se forja: só o superusuário cria/renomeia roles.
--
-- Quem ignora o RLS: superusuário e o dono da tabela (aqui bd2). É por isso que
-- a demonstração usa SET ROLE para virar o aluno. (FORCE ROW LEVEL SECURITY
-- sujeitaria também o dono, mas não o superusuário.)

-- ---------------------------------------------------------------------
-- 1. Roles
-- ---------------------------------------------------------------------
DO $$
DECLARE r text;
BEGIN
    FOREACH r IN ARRAY ARRAY['aluno','secretaria','coordenacao'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
    -- Contas de demonstração (senha fixa: ambiente acadêmico; em produção, não).
    FOREACH r IN ARRAY ARRAY['aluno_202510007','aluno_202510003','sec_demo','coord_demo'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', r, 'demo');
        END IF;
    END LOOP;
END
$$;

GRANT aluno       TO aluno_202510007, aluno_202510003;
GRANT secretaria  TO sec_demo;
GRANT coordenacao TO coord_demo;

-- ---------------------------------------------------------------------
-- 2. GRANT / REVOKE — mínimo privilégio
-- Começa tirando tudo de PUBLIC (por padrão o schema public é aberto).
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;   -- ninguém cria objeto no public
GRANT  USAGE  ON SCHEMA public TO aluno, secretaria, coordenacao;

-- Catálogo público da instituição: todos leem, ninguém além do dono altera.
GRANT SELECT ON tb_campus, tb_curso, tb_curriculo, tb_curriculo_disciplina,
                tb_disciplina, tb_pre_requisito, tb_periodo_letivo,
                tb_feriado, tb_sala, tb_turma, tb_turma_horario
    TO aluno, secretaria, coordenacao;
-- Professor: o aluno vê o nome (vw_oferta_turma é security_invoker), e-mail institucional.
GRANT SELECT ON tb_professor TO aluno, secretaria, coordenacao;

-- Views de uso geral. vw_vagas_turma roda como dono e só expõe agregados.
GRANT SELECT ON vw_oferta_turma, vw_vagas_turma TO aluno, secretaria, coordenacao;
GRANT SELECT ON vw_historico_aluno              TO aluno, secretaria, coordenacao;

-- Dados pessoais e acadêmicos (protegidos por RLS na seção 3).
GRANT SELECT ON tb_aluno, tb_matricula, tb_historico TO aluno;

-- Secretaria: opera matrículas e notas. Não apaga aluno (desligar = ativo_aluno
-- false), não toca no catálogo. DELETE de matrícula é permitido (duplicidades;
-- o histórico sai em cascata e o log guarda o rastro).
GRANT SELECT, INSERT, UPDATE         ON tb_aluno                 TO secretaria;
GRANT SELECT, INSERT, UPDATE, DELETE ON tb_matricula, tb_historico TO secretaria;
GRANT SELECT, INSERT                 ON tb_log_matricula         TO secretaria;
GRANT USAGE ON SEQUENCE tb_matricula_id_matricula_seq,
                        tb_historico_id_historico_seq,
                        tb_aluno_id_aluno_seq,
                        tb_log_matricula_id_log_matricula_seq TO secretaria;
GRANT EXECUTE ON FUNCTION fn_atualizar_indicadores() TO secretaria, coordenacao;
GRANT SELECT ON mv_indicadores_periodo TO secretaria, coordenacao;   -- matview não tem RLS: nunca ao aluno

-- Coordenação: leitura de tudo, inclusive auditoria, e ajuste de oferta com
-- privilégio por COLUNA (só vagas e professor da turma, nada mais).
GRANT SELECT ON tb_aluno, tb_matricula, tb_historico, tb_log_matricula TO coordenacao;
GRANT UPDATE (vagas_turma, id_professor) ON tb_turma TO coordenacao;

-- ---------------------------------------------------------------------
-- 3. ROW-LEVEL SECURITY
-- ---------------------------------------------------------------------
-- Função auxiliar: matrícula do aluno logado, ou NULL se a role não é de aluno.
-- STABLE: constante dentro da consulta; o planejador pode avaliá-la uma vez.
CREATE OR REPLACE FUNCTION fn_matricula_logada()
RETURNS text
LANGUAGE sql STABLE
AS $$
    SELECT CASE WHEN current_user LIKE 'aluno\_%' THEN substr(current_user, 7) END
$$;
GRANT EXECUTE ON FUNCTION fn_matricula_logada() TO aluno, secretaria, coordenacao;

ALTER TABLE tb_aluno     ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_matricula ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_historico ENABLE ROW LEVEL SECURITY;
-- Com RLS ligado e SEM política para uma role, ela vê ZERO linhas (negação padrão).

-- Equipe interna enxerga tudo (as permissões de operação já vêm dos GRANT).
CREATE POLICY pol_aluno_equipe     ON tb_aluno     FOR ALL TO secretaria, coordenacao USING (true) WITH CHECK (true);
CREATE POLICY pol_matricula_equipe ON tb_matricula FOR ALL TO secretaria, coordenacao USING (true) WITH CHECK (true);
CREATE POLICY pol_historico_equipe ON tb_historico FOR ALL TO secretaria, coordenacao USING (true) WITH CHECK (true);

-- Aluno: só as próprias linhas. Cada política é auto-suficiente (não depende
-- do RLS das outras tabelas para ser correta).
CREATE POLICY pol_aluno_proprio ON tb_aluno
    FOR SELECT TO aluno
    USING (matricula_aluno = fn_matricula_logada());

CREATE POLICY pol_matricula_propria ON tb_matricula
    FOR SELECT TO aluno
    USING (EXISTS (SELECT 1 FROM tb_aluno a
                    WHERE a.id_aluno = tb_matricula.id_aluno
                      AND a.matricula_aluno = fn_matricula_logada()));

CREATE POLICY pol_historico_proprio ON tb_historico
    FOR SELECT TO aluno
    USING (EXISTS (SELECT 1 FROM tb_matricula m
                    JOIN tb_aluno a ON a.id_aluno = m.id_aluno
                   WHERE m.id_matricula = tb_historico.id_matricula
                     AND a.matricula_aluno = fn_matricula_logada()));

-- tb_log_matricula não recebe RLS: o aluno simplesmente não tem GRANT nela.

