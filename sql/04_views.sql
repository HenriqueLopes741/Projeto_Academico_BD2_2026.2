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

- =====================================================================
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