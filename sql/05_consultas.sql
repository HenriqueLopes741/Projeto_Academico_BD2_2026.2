-- =====================================================================
-- 05_consultas.sql
-- 10 consultas de complexidade crescente, cada uma comentada
-- Frente: dividido entre os 3 integrantes
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================
--
-- TODO — obrigatórias pelo enunciado (Seção 4.1):
--   - 1 junção externa com agregação
--   - 1 consulta recursiva: árvore de pré-requisitos
--   - 1 consulta recursiva: disciplinas que um aluno já pode cursar
--   - 1 função de janela com ranking e percentil
--   - 1 função de janela com LAG para evolução do rendimento
--   - + 5 consultas adicionais de complexidade crescente


-- ---------------------------------------------------------------------
-- Q1 — Oferta de 2026/2: o que é dado, quando, onde e por quem
-- ---------------------------------------------------------------------
-- Objetivo: listar a grade horária do semestre corrente, como o aluno
-- veria no portal antes de se matricular.
--
-- Técnica: INNER JOIN em cadeia por chave estrangeira. Cada tabela
-- contribui com uma informação que a turma sozinha não tem:
--   disciplina      -> nome da disciplina
--   professor       -> quem dá a aula
--   periodo_letivo  -> filtra 2026/2 (turma só guarda o id do período)
--   turma_horario   -> dia da semana e faixa de horário
--   sala            -> onde a aula acontece
--
-- Por que INNER e não LEFT: aqui só interessam turmas que já têm
-- horário e sala definidos. Turma sem horário não aparece na grade,
-- e é exatamente esse o comportamento do INNER JOIN.
--
-- Uma turma com aula em dois dias gera duas linhas (uma por horário).
-- lower()/upper() extraem início e fim da faixa timerange [início, fim).
SELECT
    d.codigo_disciplina,
    d.nome_disciplina,
    t.codigo_turma,
    t.turno_turma,
    p.nome_professor,
    th.dia_semana_turma_horario   AS dia_semana,   -- 1 = segunda ... 7 = domingo
    lower(th.faixa_turma_horario) AS inicio,
    upper(th.faixa_turma_horario) AS fim,
    s.codigo_sala,
    t.vagas_turma
FROM turma t
JOIN disciplina     d  ON d.id_disciplina      = t.id_disciplina
JOIN professor      p  ON p.id_professor       = t.id_professor
JOIN periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
JOIN turma_horario  th ON th.id_turma          = t.id_turma
JOIN sala           s  ON s.id_sala            = th.id_sala
WHERE pl.ano_periodo_letivo      = 2026
  AND pl.semestre_periodo_letivo = 2
ORDER BY th.dia_semana_turma_horario, inicio, t.codigo_turma;
