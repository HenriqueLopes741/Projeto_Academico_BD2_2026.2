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


-- ---------------------------------------------------------------------
-- Q2 — Turmas de 2026/2 na última vaga (ou já lotadas)
-- ---------------------------------------------------------------------
-- Objetivo: achar as turmas onde resta no máximo 1 vaga. São elas que
-- o Marco 2 usa para reproduzir a disputa pela última vaga.
--
-- Técnica: GROUP BY + COUNT + HAVING.
--   GROUP BY junta as matrículas de cada turma numa linha só;
--   COUNT(*) conta quantas matrículas caíram em cada grupo;
--   HAVING filtra DEPOIS de agrupar, olhando o resultado do COUNT.
--
-- Por que HAVING e não WHERE: o WHERE roda linha a linha, antes do
-- agrupamento, e ainda não existe COUNT nesse momento. Por isso o
-- filtro de status ('ativa') fica no WHERE e o filtro de vagas
-- restantes fica no HAVING.
--
-- Só matrícula 'ativa' ocupa vaga: trancada, cancelada e concluída
-- não contam.
--
-- Limitação proposital: com JOIN interno, turma sem nenhuma matrícula
-- some do resultado. A Q3 resolve isso com LEFT JOIN.
SELECT
    t.codigo_turma,
    d.nome_disciplina,
    t.vagas_turma,
    COUNT(*)                 AS matriculados,
    t.vagas_turma - COUNT(*) AS vagas_restantes
FROM turma t
JOIN disciplina     d  ON d.id_disciplina      = t.id_disciplina
JOIN periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
JOIN matricula      m  ON m.id_turma           = t.id_turma
WHERE pl.ano_periodo_letivo      = 2026
  AND pl.semestre_periodo_letivo = 2
  AND m.status_matricula         = 'ativa'
GROUP BY t.id_turma, t.codigo_turma, d.nome_disciplina, t.vagas_turma
HAVING t.vagas_turma - COUNT(*) <= 1
ORDER BY vagas_restantes, t.codigo_turma;


-- ---------------------------------------------------------------------
-- Q3 — Catálogo inteiro x oferta de 2026/2 (junção externa + agregação)
-- ---------------------------------------------------------------------
-- Objetivo: para TODAS as disciplinas do catálogo, quantas turmas
-- foram abertas em 2026/2 e quantos alunos estão matriculados.
-- Disciplina sem oferta no semestre tem que aparecer com zero.
--
-- Técnica: LEFT JOIN + COUNT(coluna).
--   LEFT JOIN mantém toda linha da tabela da esquerda (disciplina),
--   mesmo sem par na direita; as colunas da direita vêm NULL.
--   COUNT(coluna) não conta NULL, então disciplina sem turma dá 0.
--
-- Armadilha 1 — COUNT(*) daria 1, e não 0, para disciplina sem turma:
-- a linha com NULLs existe e COUNT(*) conta linhas, não valores.
--
-- Armadilha 2 — os filtros da tabela da direita (semestre da turma e
-- status da matrícula) ficam no ON, não no WHERE. No WHERE, a
-- comparação com NULL não é verdadeira, a linha da disciplina sem
-- oferta é descartada e o LEFT JOIN vira um INNER JOIN disfarçado.
--
-- COUNT(DISTINCT t.id_turma): cada turma se repete uma vez por
-- matrícula depois do segundo JOIN; o DISTINCT conta cada turma uma vez.
SELECT
    d.codigo_disciplina,
    d.nome_disciplina,
    COUNT(DISTINCT t.id_turma) AS turmas_2026_2,
    COUNT(m.id_matricula)      AS matriculados
FROM disciplina d
LEFT JOIN turma t
       ON t.id_disciplina     = d.id_disciplina
      AND t.id_periodo_letivo = (SELECT pl.id_periodo_letivo
                                   FROM periodo_letivo pl
                                  WHERE pl.ano_periodo_letivo      = 2026
                                    AND pl.semestre_periodo_letivo = 2)
LEFT JOIN matricula m
       ON m.id_turma         = t.id_turma
      AND m.status_matricula = 'ativa'
GROUP BY d.id_disciplina, d.codigo_disciplina, d.nome_disciplina
ORDER BY matriculados DESC, d.codigo_disciplina;
