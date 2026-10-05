-- =====================================================================
-- 03_consultas.sql — 10 consultas de complexidade crescente
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================
-- Obrigatórias da Seção 4.1 marcadas com *.
--   Q1   JOIN em cadeia                 oferta de 2026/2
--   Q2   GROUP BY + HAVING              turmas na última vaga
--   Q3 * LEFT JOIN + agregação          catálogo x oferta de 2026/2
--   Q4   EXISTS / NOT EXISTS            alunos que nunca reprovaram
--   Q5   CTE + CASE                     taxa de aprovação x média geral
--   Q6 * WITH RECURSIVE                 árvore de CMP em CCO e em ECO
--   Q7 * WITH RECURSIVE + NOT EXISTS    disciplinas que a aluna pode cursar
--   Q8   janela de agregação            aluno x média da turma
--   Q9 * RANK / PERCENT_RANK / NTILE    ranking e percentil por curso
--   Q10* LAG / FIRST_VALUE              evolução do rendimento por semestre


-- ---------------------------------------------------------------------
-- Q1 — Oferta de 2026/2 (INNER JOIN em cadeia)
-- Grade do semestre: disciplina, professor, dia, horário e sala.
-- INNER: turma sem horário não entra. Uma linha por horário da turma.
-- ---------------------------------------------------------------------
SELECT
    d.codigo_disciplina,
    d.nome_disciplina,
    t.codigo_turma,
    t.turno_turma,
    p.nome_professor,
    th.dia_semana_turma_horario   AS dia_semana,   -- 1 = segunda ... 7 = domingo
    lower(th.faixa_turma_horario) AS inicio,       -- limites da faixa [início, fim)
    upper(th.faixa_turma_horario) AS fim,
    s.codigo_sala,
    t.vagas_turma
FROM tb_turma t
JOIN tb_disciplina     d  ON d.id_disciplina      = t.id_disciplina
JOIN tb_professor      p  ON p.id_professor       = t.id_professor
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_turma_horario  th ON th.id_turma          = t.id_turma
JOIN tb_sala           s  ON s.id_sala            = th.id_sala
WHERE pl.ano_periodo_letivo      = 2026
  AND pl.semestre_periodo_letivo = 2
ORDER BY th.dia_semana_turma_horario, inicio, t.codigo_turma;


-- ---------------------------------------------------------------------
-- Q2 — Turmas de 2026/2 na última vaga (GROUP BY + HAVING)
-- Turmas com no máximo 1 vaga: as usadas na disputa do Marco 2.
-- JOIN interno: turma sem matrícula some (a Q3 resolve com LEFT JOIN).
-- ---------------------------------------------------------------------
SELECT
    t.codigo_turma,
    d.nome_disciplina,
    t.vagas_turma,
    COUNT(*)                 AS matriculados,
    t.vagas_turma - COUNT(*) AS vagas_restantes
FROM tb_turma t
JOIN tb_disciplina     d  ON d.id_disciplina      = t.id_disciplina
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_matricula      m  ON m.id_turma           = t.id_turma
WHERE pl.ano_periodo_letivo      = 2026
  AND pl.semestre_periodo_letivo = 2
  AND m.status_matricula         = 'ativa'         -- só matrícula ativa ocupa vaga
GROUP BY t.id_turma, t.codigo_turma, d.nome_disciplina, t.vagas_turma
HAVING t.vagas_turma - COUNT(*) <= 1               -- HAVING: filtra depois do COUNT
ORDER BY vagas_restantes, t.codigo_turma;


-- ---------------------------------------------------------------------
-- Q3 — Catálogo inteiro x oferta de 2026/2 (LEFT JOIN + COUNT)
-- Toda disciplina aparece; sem oferta no semestre, com zero.
-- ---------------------------------------------------------------------
SELECT
    d.codigo_disciplina,
    d.nome_disciplina,
    COUNT(DISTINCT t.id_turma) AS turmas_2026_2,   -- DISTINCT: turma se repete por matrícula
    COUNT(m.id_matricula)      AS matriculados     -- COUNT(col) ignora NULL; COUNT(*) daria 1
FROM tb_disciplina d
LEFT JOIN tb_turma t                               -- filtros da direita no ON: no WHERE, viraria INNER
       ON t.id_disciplina     = d.id_disciplina
      AND t.id_periodo_letivo = (SELECT pl.id_periodo_letivo
                                   FROM tb_periodo_letivo pl
                                  WHERE pl.ano_periodo_letivo      = 2026
                                    AND pl.semestre_periodo_letivo = 2)
LEFT JOIN tb_matricula m
       ON m.id_turma         = t.id_turma
      AND m.status_matricula = 'ativa'
GROUP BY d.id_disciplina, d.codigo_disciplina, d.nome_disciplina
ORDER BY matriculados DESC, d.codigo_disciplina;


-- ---------------------------------------------------------------------
-- Q4 — Alunos que nunca reprovaram (EXISTS / NOT EXISTS correlacionados)
-- Ao menos uma aprovação e nenhuma reprovação, por nota ou por falta.
-- ---------------------------------------------------------------------
SELECT
    a.matricula_aluno,
    a.nome_aluno,
    c.codigo_curso
FROM tb_aluno a
JOIN tb_curso c ON c.id_curso = a.id_curso
WHERE EXISTS (                                     -- tira o calouro sem nada concluído
        SELECT 1
          FROM tb_matricula m
          JOIN tb_historico h ON h.id_matricula = m.id_matricula
         WHERE m.id_aluno = a.id_aluno
           AND h.situacao_historico = 'aprovado'
      )
  AND NOT EXISTS (                                 -- NOT EXISTS, não NOT IN: imune a NULL
        SELECT 1
          FROM tb_matricula m
          JOIN tb_historico h ON h.id_matricula = m.id_matricula
         WHERE m.id_aluno = a.id_aluno
           AND h.situacao_historico IN ('reprovado_nota',
                                        'reprovado_falta',
                                        'reprovado_nota_falta')
      )
ORDER BY c.codigo_curso, a.nome_aluno;


-- ---------------------------------------------------------------------
-- Q5 — Taxa de aprovação por disciplina x média geral (CTE + CASE)
-- Aprovados e reprovados por disciplina, comparados à taxa da
-- instituição com margem de 5 pontos.
-- ---------------------------------------------------------------------
WITH resultado AS (                                -- contagens por disciplina
    SELECT
        t.id_disciplina,
        COUNT(*) AS concluintes,
        SUM(CASE WHEN h.situacao_historico = 'aprovado'
                 THEN 1 ELSE 0 END) AS aprovados,  -- CASE no SUM: contagem condicional
        SUM(CASE WHEN h.situacao_historico IN ('reprovado_nota', 'reprovado_nota_falta')
                 THEN 1 ELSE 0 END) AS repr_nota,
        SUM(CASE WHEN h.situacao_historico IN ('reprovado_falta', 'reprovado_nota_falta')
                 THEN 1 ELSE 0 END) AS repr_falta
    FROM tb_historico h
    JOIN tb_matricula m ON m.id_matricula = h.id_matricula
    JOIN tb_turma     t ON t.id_turma     = m.id_turma
    WHERE h.situacao_historico NOT IN ('cursando', 'trancada')  -- só quem terminou
    GROUP BY t.id_disciplina
),
geral AS (                                         -- taxa da instituição inteira
    SELECT 100.0 * SUM(aprovados) / SUM(concluintes) AS taxa_geral  -- 100.0: evita divisão inteira
    FROM resultado
)
SELECT
    d.codigo_disciplina,
    d.nome_disciplina,
    r.concluintes,
    r.aprovados,
    r.repr_nota,
    r.repr_falta,
    ROUND(100.0 * r.aprovados / r.concluintes, 1) AS taxa_aprovacao,
    ROUND(g.taxa_geral, 1)                         AS taxa_geral,
    CASE
        WHEN 100.0 * r.aprovados / r.concluintes < g.taxa_geral - 5 THEN 'abaixo da média'
        WHEN 100.0 * r.aprovados / r.concluintes > g.taxa_geral + 5 THEN 'acima da média'
        ELSE 'na média'
    END AS situacao
FROM resultado r
JOIN tb_disciplina d ON d.id_disciplina = r.id_disciplina
CROSS JOIN geral g
ORDER BY taxa_aprovacao, d.codigo_disciplina;


-- ---------------------------------------------------------------------
-- Q6 — Árvore de pré-requisitos de Compiladores em CCO e ECO (WITH RECURSIVE)
-- Tudo que vem antes de CMP, direta ou indiretamente, por currículo.
-- As árvores diferem: Linguagens Formais exige TCP em CCO e ED em ECO.
-- ---------------------------------------------------------------------
WITH RECURSIVE arvore AS (
    -- âncora: requisitos diretos de CMP (nível 1)
    SELECT
        pr.id_curriculo,
        pr.id_disciplina_requisito                          AS id_requisito,
        1                                                   AS nivel,
        ARRAY[pr.id_disciplina, pr.id_disciplina_requisito] AS caminho
    FROM tb_pre_requisito pr
    JOIN tb_disciplina d ON d.id_disciplina = pr.id_disciplina
    WHERE d.codigo_disciplina      = 'CMP'
      AND pr.vinculo_pre_requisito = 'pre_requisito'  -- co-requisito não vem antes

    UNION ALL

    -- recursiva: requisitos dos requisitos; para quando não acha linha nova
    SELECT
        a.id_curriculo,
        pr.id_disciplina_requisito,
        a.nivel + 1,
        a.caminho || pr.id_disciplina_requisito
    FROM arvore a
    JOIN tb_pre_requisito pr
      ON pr.id_curriculo  = a.id_curriculo          -- não mistura currículos
     AND pr.id_disciplina = a.id_requisito
    WHERE pr.vinculo_pre_requisito = 'pre_requisito'
      AND NOT (pr.id_disciplina_requisito = ANY (a.caminho))  -- trava contra ciclo
)
SELECT
    c.codigo_curso,
    a.nivel,
    repeat('    ', a.nivel - 1) || d.codigo_disciplina AS requisito,
    d.nome_disciplina,
    (SELECT string_agg(dc.codigo_disciplina, ' <- ' ORDER BY x.ord)
       FROM unnest(a.caminho) WITH ORDINALITY AS x(id, ord)
       JOIN tb_disciplina dc ON dc.id_disciplina = x.id) AS caminho
FROM arvore a
JOIN tb_disciplina d  ON d.id_disciplina = a.id_requisito
JOIN tb_curriculo cu  ON cu.id_curriculo = a.id_curriculo
JOIN tb_curso c       ON c.id_curso      = cu.id_curso
ORDER BY c.codigo_curso, a.caminho;


-- ---------------------------------------------------------------------
-- Q7 — Disciplinas que a aluna 202510007 já pode cursar (WITH RECURSIVE + NOT EXISTS)
-- Do currículo dela: não aprovadas, não em curso e com TODOS os
-- requisitos cumpridos, diretos e indiretos (fecho transitivo).
-- ---------------------------------------------------------------------
WITH RECURSIVE
aluna AS (
    SELECT id_aluno, id_curriculo
    FROM tb_aluno
    WHERE matricula_aluno = '202510007'
),
requisitos AS (
    -- âncora: requisito direto, só no currículo da aluna
    SELECT
        pr.id_curriculo,
        pr.id_disciplina,
        pr.id_disciplina_requisito AS id_requisito,
        ARRAY[pr.id_disciplina, pr.id_disciplina_requisito] AS caminho
    FROM tb_pre_requisito pr
    JOIN aluna al ON al.id_curriculo = pr.id_curriculo
    WHERE pr.vinculo_pre_requisito = 'pre_requisito'

    UNION ALL

    -- recursiva: o requisito do requisito também é requisito
    SELECT
        r.id_curriculo,
        r.id_disciplina,
        pr.id_disciplina_requisito,
        r.caminho || pr.id_disciplina_requisito
    FROM requisitos r
    JOIN tb_pre_requisito pr
      ON pr.id_curriculo  = r.id_curriculo
     AND pr.id_disciplina = r.id_requisito
    WHERE pr.vinculo_pre_requisito = 'pre_requisito'
      AND NOT (pr.id_disciplina_requisito = ANY (r.caminho))
),
historico_aluna AS (
    SELECT t.id_disciplina, h.situacao_historico
    FROM aluna al
    JOIN tb_matricula m ON m.id_aluno     = al.id_aluno
    JOIN tb_historico h ON h.id_matricula = m.id_matricula
    JOIN tb_turma     t ON t.id_turma     = m.id_turma
),
cumpridas AS (
    SELECT DISTINCT id_disciplina
    FROM historico_aluna
    WHERE situacao_historico = 'aprovado'
)
SELECT
    cd.periodo_curriculo_disciplina AS periodo,
    d.codigo_disciplina,
    d.nome_disciplina,
    cd.tipo_curriculo_disciplina    AS tipo
FROM aluna al
JOIN tb_curriculo_disciplina cd ON cd.id_curriculo = al.id_curriculo
JOIN tb_disciplina d            ON d.id_disciplina = cd.id_disciplina
WHERE NOT EXISTS (                       -- ainda não aprovada
        SELECT 1 FROM cumpridas c
         WHERE c.id_disciplina = cd.id_disciplina)
  AND NOT EXISTS (                       -- não está cursando agora
        SELECT 1 FROM historico_aluna ha
         WHERE ha.id_disciplina = cd.id_disciplina
           AND ha.situacao_historico = 'cursando')
  AND NOT EXISTS (                       -- nenhum requisito pendente (sem requisito: passa)
        SELECT 1 FROM requisitos r
         WHERE r.id_disciplina = cd.id_disciplina
           AND r.id_requisito NOT IN (SELECT id_disciplina FROM cumpridas))  -- seguro: nunca NULL
ORDER BY cd.periodo_curriculo_disciplina, d.codigo_disciplina;


-- ---------------------------------------------------------------------
-- Q8 — Cada aluno x a própria turma (janela de agregação)
-- Turma CCODM2A-ED (2026/1): média do aluno ao lado da média, maior e
-- menor da turma. OVER repete o agregado em cada linha; GROUP BY sumiria
-- com o aluno.
-- ---------------------------------------------------------------------
SELECT
    a.matricula_aluno,
    a.nome_aluno,
    h.media_final_historico                          AS media_aluno,
    h.situacao_historico,
    ROUND(AVG(h.media_final_historico) OVER turma_w, 2) AS media_turma,
    MAX(h.media_final_historico)       OVER turma_w     AS maior_turma,
    MIN(h.media_final_historico)       OVER turma_w     AS menor_turma,
    ROUND(h.media_final_historico
          - AVG(h.media_final_historico) OVER turma_w, 2) AS diferenca
FROM tb_historico h
JOIN tb_matricula m ON m.id_matricula = h.id_matricula
JOIN tb_aluno     a ON a.id_aluno     = m.id_aluno
JOIN tb_turma     t ON t.id_turma     = m.id_turma
WHERE t.codigo_turma = 'CCODM2A-ED'
  AND h.media_final_historico IS NOT NULL          -- sem média não entra (NULL não é zero)
WINDOW turma_w AS (PARTITION BY m.id_turma)        -- janela nomeada: cada turma é um grupo
ORDER BY diferenca DESC;


-- ---------------------------------------------------------------------
-- Q9 — Ranking e percentil dos alunos dentro do curso (janela de ranking)
-- Top 10 de cada curso pela média geral, com posição, percentil e quartil.
-- ---------------------------------------------------------------------
WITH media_aluno AS (
    SELECT
        a.id_aluno,
        a.id_curso,
        a.matricula_aluno,
        a.nome_aluno,
        ROUND(AVG(h.media_final_historico), 2) AS media_geral
    FROM tb_aluno a
    JOIN tb_matricula m ON m.id_aluno     = a.id_aluno
    JOIN tb_historico h ON h.id_matricula = m.id_matricula
    WHERE h.media_final_historico IS NOT NULL
      AND h.situacao_historico NOT IN ('cursando', 'trancada')
    GROUP BY a.id_aluno
),
ranking AS (
    SELECT
        ma.*,
        RANK()       OVER curso_w AS posicao,        -- empate pula: 1, 2, 2, 4
        DENSE_RANK() OVER curso_w AS posicao_densa,  -- empate não pula: 1, 2, 2, 3
        ROUND((1 - PERCENT_RANK() OVER curso_w)::numeric * 100, 1) AS a_frente_de_pct,
        NTILE(4)     OVER curso_w AS quartil         -- 1 = 25% melhores
    FROM media_aluno ma
    WINDOW curso_w AS (PARTITION BY ma.id_curso ORDER BY ma.media_geral DESC)
)
SELECT
    c.codigo_curso,
    r.posicao,
    r.posicao_densa,
    r.matricula_aluno,
    r.nome_aluno,
    r.media_geral,
    r.a_frente_de_pct,
    r.quartil
FROM ranking r
JOIN tb_curso c ON c.id_curso = r.id_curso
WHERE r.posicao <= 10                              -- fora da CTE: janela roda depois do WHERE
ORDER BY c.codigo_curso, r.posicao, r.nome_aluno;


-- ---------------------------------------------------------------------
-- Q10 — Evolução do rendimento semestre a semestre (LAG / FIRST_VALUE)
-- Média de cada semestre x a do anterior e a do ingresso, para a 1ª de
-- CCO na Q9 (202510003) e a aluna da Q7 (202510007).
-- ---------------------------------------------------------------------
WITH media_semestre AS (                           -- uma linha por aluno e semestre
    SELECT
        a.id_aluno,
        a.matricula_aluno,
        a.nome_aluno,
        pl.ano_periodo_letivo                  AS ano,
        pl.semestre_periodo_letivo             AS semestre,
        ROUND(AVG(h.media_final_historico), 2) AS media
    FROM tb_aluno a
    JOIN tb_matricula      m  ON m.id_aluno           = a.id_aluno
    JOIN tb_historico      h  ON h.id_matricula       = m.id_matricula
    JOIN tb_turma          t  ON t.id_turma           = m.id_turma
    JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
    WHERE h.media_final_historico IS NOT NULL      -- 2026/2 fica de fora: sem média ainda
      AND h.situacao_historico NOT IN ('cursando', 'trancada')
    GROUP BY a.id_aluno, pl.ano_periodo_letivo, pl.semestre_periodo_letivo
),
evolucao AS (
    SELECT
        ms.*,
        LAG(ms.media)         OVER aluno_w AS media_anterior,  -- linha anterior, sem self-join
        ms.media - LAG(ms.media) OVER aluno_w AS variacao,
        ms.media - FIRST_VALUE(ms.media) OVER aluno_w AS desde_ingresso
    FROM media_semestre ms
    WINDOW aluno_w AS (PARTITION BY ms.id_aluno ORDER BY ms.ano, ms.semestre)
)
SELECT
    e.matricula_aluno,
    e.nome_aluno,
    e.ano || '/' || e.semestre AS periodo,
    e.media,
    e.media_anterior,
    e.variacao,
    e.desde_ingresso,
    CASE
        WHEN e.variacao IS NULL THEN 'início'      -- 1º semestre: LAG devolve NULL
        WHEN e.variacao > 0     THEN 'subiu'
        WHEN e.variacao < 0     THEN 'caiu'
        ELSE 'estável'
    END AS tendencia
FROM evolucao e
WHERE e.matricula_aluno IN ('202510003', '202510007')
ORDER BY e.matricula_aluno, e.ano, e.semestre;
