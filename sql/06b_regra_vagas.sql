-- =====================================================================
-- 06b_regra_vagas.sql
-- Regra de vagas aplicada pelo banco: função + trigger em public.tb_matricula
-- Frente: Transações e Concorrência
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================
--
-- EXECUÇÃO
--   Depois de 01_ddl.sql e 02_carga.sql, e antes de 06_transacoes.sql:
--   docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U bd2 -d matricula < ./sql/06b_regra_vagas.sql
--
-- O QUE FAZ
--   1. Valida que nenhuma turma já ultrapassa vagas_turma. Se algum dado
--      violar a regra, o arquivo para antes de criar a trigger.
--   2. Cria a função public.fn_verifica_vaga() e a trigger trg_verifica_vaga,
--      que roda antes de INSERT e de UPDATE de status/turma em tb_matricula.
--      Para cada matrícula que ocupa vaga, a função:
--        a) trava a turma com FOR UPDATE (matrículas concorrentes esperam);
--        b) conta as matrículas que ocupam vaga, sem contar a própria linha;
--        c) recusa a operação se a turma já estiver cheia.
--
-- POR QUE A REGRA NÃO RODA DURANTE A CARGA
--   A carga importa histórico (matrículas concluídas e trancadas), e não
--   operações de matrícula. Criar a trigger depois da carga evita verificar
--   3.320 linhas sem ganho, e a validação do passo 1 garante que a carga
--   já respeita o limite.
--
-- POR QUE SECURITY DEFINER
--   A contagem precisa enxergar todas as matrículas da turma. Como a função
--   roda com os privilégios do dono do banco, uma política de RLS que
--   esconda matrículas de outros alunos não altera o resultado.
--
-- REGRA DE OCUPAÇÃO
--   Ocupa vaga: status_matricula IN ('ativa', 'concluida'), a mesma regra
--   de 02_carga.sql e de 06_transacoes.sql.

-- ---------------------------------------------------------------------
-- 1. Validação: a carga não pode já estar acima das vagas
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_violacoes integer;
BEGIN
    SELECT COUNT(*) INTO v_violacoes
      FROM (
          SELECT t.id_turma
            FROM public.tb_turma t
            LEFT JOIN public.tb_matricula m
                   ON m.id_turma = t.id_turma
                  AND m.status_matricula IN ('ativa', 'concluida')
           GROUP BY t.id_turma, t.vagas_turma
          HAVING COUNT(m.id_matricula) > t.vagas_turma
      ) x;

    IF v_violacoes > 0 THEN
        RAISE EXCEPTION '% turma(s) já acima de vagas_turma; corrija a carga antes de criar a regra',
            v_violacoes;
    END IF;
END
$$;

-- ---------------------------------------------------------------------
-- 2. Função de verificação
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_verifica_vaga() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_vagas    smallint;
    v_ocupadas integer;
BEGIN
    -- Só status que ocupam vaga precisam de verificação.
    IF NEW.status_matricula NOT IN ('ativa', 'concluida') THEN
        RETURN NEW;
    END IF;

    -- Trava a turma. Outra matrícula na mesma turma espera aqui até o COMMIT.
    SELECT vagas_turma INTO v_vagas
      FROM public.tb_turma
     WHERE id_turma = NEW.id_turma
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'turma % não existe', NEW.id_turma;
    END IF;

    -- Conta as matrículas que ocupam vaga, exceto a própria linha
    -- (importante em UPDATE, para não contar a linha que está sendo alterada).
    SELECT COUNT(*) INTO v_ocupadas
      FROM public.tb_matricula
     WHERE id_turma = NEW.id_turma
       AND status_matricula IN ('ativa', 'concluida')
       AND id_matricula <> NEW.id_matricula;

    IF v_ocupadas >= v_vagas THEN
        RAISE EXCEPTION 'turma % sem vagas (% ocupadas de %)',
            NEW.id_turma, v_ocupadas, v_vagas
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. Trigger
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_verifica_vaga ON public.tb_matricula;

CREATE TRIGGER trg_verifica_vaga
    BEFORE INSERT OR UPDATE OF status_matricula, id_turma ON public.tb_matricula
    FOR EACH ROW EXECUTE FUNCTION public.fn_verifica_vaga();

COMMENT ON FUNCTION public.fn_verifica_vaga() IS
    'Impede matrícula acima de vagas_turma. Trava a turma com FOR UPDATE.';