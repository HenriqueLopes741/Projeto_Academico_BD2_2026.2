-- =====================================================================
-- 04_views.sql
-- 3 views (oferta, vagas, histórico) + 1 materialized view de indicadores
-- Frente: Administração e Operação
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================
--
-- Pré-condição: 01_ddl.sql e 02_carga.sql já rodados.
-- Roda ANTES de 07_seguranca_rls.sql (que dá os GRANTs sobre estes objetos).
--
-- O QUE É UMA VIEW (e por que usar)
--   View = consulta com nome. Não guarda dados: a cada SELECT o banco
--   reexecuta a consulta sobre as tabelas. Serve para (1) dar um nome à
--   consulta que todo mundo repete (oferta, vagas) e (2) ser a "janela" que
--   expomos a um papel sem abrir as tabelas por trás (ver 07).
--
-- O QUE É UMA MATERIALIZED VIEW
--   Mesma consulta, mas o resultado é GRAVADO em disco. Ler é rápido
--   (é como ler uma tabela); o preço é que o dado envelhece até alguém
--   rodar REFRESH. Vale a pena quando a consulta é cara e o dado muda
--   pouco — é o caso de indicadores acadêmicos.
--
-- DUAS DECISÕES DE PROJETO (defender na arguição)
--   1. "Ocupa vaga" = matrícula 'ativa' ou 'concluida'. Trancada e
--      cancelada liberam a vaga. É a mesma regra da conferência de
--      02_carga.sql. Em 2026/2 só existem 'ativa', então a Q2 (que conta só
--      'ativa') e vw_vagas dão o mesmo resultado. O 06_transacoes.sql tem de
--      usar a MESMA regra.
--   2. vw_historico_aluno é security_invoker: roda com os privilégios (e a
--      RLS) de QUEM CONSULTA, não de quem criou a view. Sem isso, a view
--      (criada pelo dono) enxergaria tudo e furaria a RLS do 07.
--      As outras duas views só mostram dados públicos/agregados e rodam
--      com os direitos do dono (padrão).
 
-- ---------------------------------------------------------------------
-- 1. vw_oferta — oferta de turmas por período, com os horários numa linha
-- ---------------------------------------------------------------------
-- Uma linha por TURMA (a Q1 devolve uma por horário). LEFT JOIN LATERAL:
-- turma sem horário continua aparecendo, com horarios NULL.

CREATE OR REPLACE VIEW vw_oferta_turma AS
SELECT
    t.id_turma,
    t.codigo_turma,
    pl.ano_periodo_letivo                                   AS ano,
    pl.semestre_periodo_letivo                              AS semestre,
    pl.ano_periodo_letivo || '/' || pl.semestre_periodo_letivo AS periodo,
    d.codigo_disciplina,
    d.nome_disciplina,
    d.ch_total_disciplina,
    t.turno_turma,
    p.nome_professor,
    t.vagas_turma,
    h.horarios
FROM tb_turma t
JOIN tb_disciplina     d  ON d.id_disciplina      = t.id_disciplina
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_professor      p  ON p.id_professor       = t.id_professor
LEFT JOIN LATERAL (
    SELECT string_agg(
               (ARRAY['seg','ter','qua','qui','sex','sáb','dom'])[th.dia_semana_turma_horario]
               || ' ' || left(lower(th.faixa_turma_horario)::text, 5)
               || '-'  || left(upper(th.faixa_turma_horario)::text, 5)
               || ' (' || s.codigo_sala || ')',
               '; ' ORDER BY th.dia_semana_turma_horario, lower(th.faixa_turma_horario)
           ) AS horarios
      FROM tb_turma_horario th
      JOIN tb_sala s ON s.id_sala = th.id_sala
     WHERE th.id_turma = t.id_turma
) h ON true;

COMMENT ON VIEW vw_oferta_turma IS
    'Oferta de turmas: disciplina, professor, período e horários (dia, faixa, sala). Turma sem horário aparece com horarios NULL.';

-- =====================================================================
-- VIEW 2 — VAGAS POR TURMA
-- =====================================================================
-- Ocupação calculada na hora (não materializada): é o dado que a disputa pela
-- última vaga (06_transacoes.sql) precisa ver atualizado. LEFT JOIN para a
-- turma sem nenhuma matrícula aparecer com 0 ocupadas.
-- O filtro de status fica no ON: no WHERE, o LEFT JOIN viraria INNER.
 
CREATE OR REPLACE VIEW vw_vagas_turma AS
SELECT
    t.id_turma,
    t.codigo_turma,
    pl.ano_periodo_letivo || '/' || pl.semestre_periodo_letivo AS periodo,
    d.codigo_disciplina,
    d.nome_disciplina,
    t.vagas_turma,
    COUNT(m.id_matricula)                          AS vagas_ocupadas,
    t.vagas_turma - COUNT(m.id_matricula)          AS vagas_livres,
    ROUND(100.0 * COUNT(m.id_matricula) / t.vagas_turma, 1) AS ocupacao_pct,
    CASE
        WHEN COUNT(m.id_matricula) >  t.vagas_turma THEN 'excedida'   -- nunca deveria ocorrer
        WHEN COUNT(m.id_matricula) =  t.vagas_turma THEN 'lotada'
        WHEN COUNT(m.id_matricula) =  t.vagas_turma - 1 THEN 'ultima vaga'
        ELSE 'com vagas'
    END                                            AS situacao_vagas
FROM tb_turma t
JOIN tb_disciplina     d  ON d.id_disciplina      = t.id_disciplina
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
LEFT JOIN tb_matricula m
       ON m.id_turma         = t.id_turma
      AND m.status_matricula IN ('ativa', 'concluida')
GROUP BY t.id_turma, t.codigo_turma, t.vagas_turma,
         pl.ano_periodo_letivo, pl.semestre_periodo_letivo,
         d.codigo_disciplina, d.nome_disciplina;
 
COMMENT ON VIEW vw_vagas_turma IS
    'Vagas por turma. Ocupam vaga as matrículas ativa e concluida; trancada e cancelada liberam. Calculada em tempo real.';

 
-- =====================================================================
-- VIEW 3 — HISTÓRICO DO ALUNO
-- =====================================================================
-- Uma linha por matrícula do aluno: período, disciplina, turma, notas, média,
-- frequência e situação. Expõe id_aluno e matricula_aluno para as políticas de
-- RLS e para filtro (WHERE matricula_aluno = '...').
-- security_invoker: a RLS das tabelas-base vale para quem consulta a view.
 
CREATE OR REPLACE VIEW vw_historico_aluno
WITH (security_invoker = true) AS
SELECT
    a.id_aluno,
    a.matricula_aluno,
    a.nome_aluno,
    c.codigo_curso,
    pl.ano_periodo_letivo || '/' || pl.semestre_periodo_letivo AS periodo,
    d.codigo_disciplina,
    d.nome_disciplina,
    t.codigo_turma,
    m.status_matricula,
    h.nota_a1_historico,
    h.nota_a2_historico,
    h.nota_p3_historico,
    h.media_final_historico,
    h.frequencia_historico,
    h.situacao_historico
FROM tb_historico h
JOIN tb_matricula      m  ON m.id_matricula       = h.id_matricula
JOIN tb_aluno          a  ON a.id_aluno           = m.id_aluno
JOIN tb_curso          c  ON c.id_curso           = a.id_curso
JOIN tb_turma          t  ON t.id_turma           = m.id_turma
JOIN tb_disciplina     d  ON d.id_disciplina      = t.id_disciplina
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo;
 
COMMENT ON VIEW vw_historico_aluno IS
    'Histórico acadêmico por matrícula. security_invoker: respeita a RLS das tabelas-base (aluno só vê o próprio histórico).';

-- =====================================================================
-- MATERIALIZED VIEW — INDICADORES POR PERÍODO E DISCIPLINA
-- =====================================================================
-- Agrega o histórico inteiro (3.320 matrículas hoje; cresce a cada semestre),
-- o que é caro para recalcular a cada consulta do painel da coordenação.
--
--   matriculas_ocupantes: ativa + concluida (mesma regra de vaga)
--   trancadas:            matrículas trancadas
--   concluintes:          quem já tem resultado final (exclui cursando/trancada)
--   taxa_aprovacao:       aprovados / concluintes (NULL se não há concluintes,
--                         ex.: 2026/2, semestre em andamento)
--   media_geral:          média das médias finais já calculadas (NULL ignorado)
--   frequencia_media:     frequência média dos concluintes

DROP MATERIALIZED VIEW IF EXISTS mv_indicadores_disciplina;

CREATE MATERIALIZED VIEW mv_indicadores_disciplina AS
SELECT
    pl.id_periodo_letivo,
    d.id_disciplina,
    pl.ano_periodo_letivo || '/' || pl.semestre_periodo_letivo AS periodo,
    d.codigo_disciplina,
    d.nome_disciplina,
    COUNT(DISTINCT t.id_turma)                                              AS turmas,
    COUNT(*) FILTER (WHERE m.status_matricula IN ('ativa', 'concluida'))   AS matriculas_ocupantes,
    COUNT(*) FILTER (WHERE m.status_matricula = 'trancada')                AS trancadas,
    COUNT(*) FILTER (WHERE h.situacao_historico NOT IN ('cursando', 'trancada'))   AS concluintes,
    COUNT(*) FILTER (WHERE h.situacao_historico = 'aprovado')              AS aprovados,
    COUNT(*) FILTER (WHERE h.situacao_historico IN ('reprovado_nota', 'reprovado_nota_falta'))  AS reprovados_nota,
    COUNT(*) FILTER (WHERE h.situacao_historico IN ('reprovado_falta', 'reprovado_nota_falta')) AS reprovados_falta,
    ROUND(100.0 * COUNT(*) FILTER (WHERE h.situacao_historico = 'aprovado')
          / NULLIF(COUNT(*) FILTER (WHERE h.situacao_historico NOT IN ('cursando', 'trancada')), 0), 1)
                                                                            AS taxa_aprovacao,
    ROUND(AVG(h.media_final_historico), 2)                                  AS media_geral,
    ROUND(AVG(h.frequencia_historico)
          FILTER (WHERE h.situacao_historico NOT IN ('cursando', 'trancada')), 1)
                                                                            AS frequencia_media
FROM tb_turma t
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_disciplina     d  ON d.id_disciplina      = t.id_disciplina
JOIN tb_matricula      m  ON m.id_turma           = t.id_turma
JOIN tb_historico      h  ON h.id_matricula       = m.id_matricula
GROUP BY pl.id_periodo_letivo, pl.ano_periodo_letivo, pl.semestre_periodo_letivo,
         d.id_disciplina, d.codigo_disciplina, d.nome_disciplina
WITH DATA;

-- Índice único: obrigatório para REFRESH MATERIALIZED VIEW CONCURRENTLY
-- (atualiza sem bloquear as leituras). Fica aqui, e não em 05_indices.sql,
-- porque é requisito de funcionamento da política de atualização.
CREATE UNIQUE INDEX uq_mv_indicadores_periodo_disciplina
    ON mv_indicadores_disciplina (id_periodo_letivo, id_disciplina);

COMMENT ON MATERIALIZED VIEW mv_indicadores_disciplina IS
    'Indicadores por período e disciplina (aprovação, médias, frequência). Atualizar com REFRESH ... CONCURRENTLY; ver política em 04_views.sql.';

-- ---------------------------------------------------------------------
-- POLÍTICA DE ATUALIZAÇÃO DA MATERIALIZED VIEW
-- ---------------------------------------------------------------------
-- Escolha: REFRESH MATERIALIZED VIEW CONCURRENTLY, executado de forma
-- agendada e sob demanda (manual), NÃO por trigger.
--
--   Quando executar:
--     1. após o lançamento de notas/fechamento de um período letivo;
--     2. diariamente, fora do horário de pico (ex.: 03:00), via cron do
--        sistema operacional ou pg_cron, se a extensão estiver disponível;
--     3. manualmente pela secretaria/coordenação antes de reuniões.
--
--   Por que não trigger:
--     - o REFRESH recalcula a visão inteira; disparado a cada INSERT/UPDATE
--       em matrícula ou histórico, penalizaria exatamente o caminho quente da
--       matrícula (a disputa pela última vaga de 06_transacoes.sql);
--     - indicadores de aprovação e média só mudam de verdade quando as notas
--       são consolidadas, não a cada matrícula. Defasagem de horas é aceitável
--       para um painel gerencial.
--
--   Por que CONCURRENTLY:
--     - não bloqueia os SELECTs da coordenação durante o refresh (exige o
--       índice único acima); custo: um pouco mais lento que o refresh simples.
--       Não pode rodar dentro de bloco BEGIN/COMMIT.
--
--   Dado que precisa estar em tempo real (vagas) NÃO usa a materialized view:
--   vem de vw_vagas_turma, calculada na consulta.
--
--   Comando (psql / pgAdmin):
--     REFRESH MATERIALIZED VIEW CONCURRENTLY mv_indicadores_disciplina;
--
--   Exemplo de agendamento no host (crontab):
--     0 3 * * * docker compose -f /caminho/docker-compose.yml exec -T postgres \
--       psql -U bd2 -d matricula -c "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_indicadores_disciplina;"

-- =====================================================================
-- CONFERÊNCIA
-- =====================================================================
-- Para o script aqui se algo estiver incoerente com a carga.

DO $$
DECLARE
    n_turmas  integer;
    n_vagas   integer;
    n_oferta  integer;
    violacoes integer;
BEGIN
    SELECT count(*) INTO n_turmas FROM tb_turma;
    SELECT count(*) INTO n_vagas  FROM vw_vagas_turma;
    SELECT count(*) INTO n_oferta FROM vw_oferta_turma;

    -- uma linha por turma nas duas views (os joins não duplicam nem perdem turma)
    IF n_vagas <> n_turmas OR n_oferta <> n_turmas THEN
        RAISE EXCEPTION 'views: % turmas, % em vw_vagas_turma, % em vw_oferta_turma',
            n_turmas, n_vagas, n_oferta;
    END IF;

    -- cenário da última vaga: toda turma de 2026/2 com exatamente 1 vaga livre
    SELECT count(*) INTO violacoes
      FROM vw_vagas_turma
     WHERE periodo = '2026/2' AND vagas_livres <> 1;
    IF violacoes > 0 THEN
        RAISE EXCEPTION 'vw_vagas_turma: % turma(s) de 2026/2 sem exatamente 1 vaga livre', violacoes;
    END IF;

    -- nenhuma turma acima da capacidade
    SELECT count(*) INTO violacoes FROM vw_vagas_turma WHERE vagas_livres < 0;
    IF violacoes > 0 THEN
        RAISE EXCEPTION 'vw_vagas_turma: % turma(s) com vagas excedidas', violacoes;
    END IF;

    -- a view de histórico tem uma linha por matrícula
    SELECT count(*) INTO violacoes
      FROM (SELECT (SELECT count(*) FROM vw_historico_aluno) AS v,
                   (SELECT count(*) FROM tb_matricula)       AS m) x
     WHERE x.v <> x.m;
    IF violacoes > 0 THEN
        RAISE EXCEPTION 'vw_historico_aluno: contagem diferente de tb_matricula';
    END IF;

    -- a materialized view foi populada
    IF NOT EXISTS (SELECT 1 FROM mv_indicadores_disciplina) THEN
        RAISE EXCEPTION 'mv_indicadores_disciplina vazia após a criação';
    END IF;

    RAISE NOTICE 'views ok: % turmas, histórico e indicadores conferidos', n_turmas;
END
$$;