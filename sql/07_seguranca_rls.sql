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

