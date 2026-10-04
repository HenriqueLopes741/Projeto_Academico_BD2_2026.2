-- =====================================================================
-- 05_consultas.sql
-- 10 consultas de complexidade crescente, cada uma comentada
-- Frente: dividido entre os 3 integrantes
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================
--
-- Índice (as obrigatórias da Seção 4.1 estão marcadas com *):
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


-- ---------------------------------------------------------------------
-- Q4 — Alunos que nunca reprovaram (subconsultas com EXISTS / NOT EXISTS)
-- ---------------------------------------------------------------------
-- Objetivo: listar quem já concluiu ao menos uma disciplina e não tem
-- nenhuma reprovação no histórico (nem por nota, nem por falta).
--
-- Técnica: subconsulta correlacionada com EXISTS e NOT EXISTS.
--   "Correlacionada" porque a subconsulta usa a.id_aluno da consulta de
--   fora: ela é avaliada para cada aluno.
--   EXISTS só pergunta "existe pelo menos uma linha?"; para na primeira
--   que encontra e não importa o que vem no SELECT (por isso SELECT 1).
--
-- Por que o EXISTS do meio: sem ele, calouro sem nenhuma disciplina
-- concluída também "nunca reprovou" e entraria na lista por vacuidade.
--
-- Por que NOT EXISTS e não NOT IN: se a subconsulta do NOT IN devolver
-- um único NULL, x NOT IN (...) vira NULL para todo mundo e a consulta
-- volta vazia. NOT EXISTS não tem esse problema.
SELECT
    a.matricula_aluno,
    a.nome_aluno,
    c.codigo_curso
FROM aluno a
JOIN curso c ON c.id_curso = a.id_curso
WHERE EXISTS (
        SELECT 1
          FROM matricula m
          JOIN historico h ON h.id_matricula = m.id_matricula
         WHERE m.id_aluno = a.id_aluno
           AND h.situacao_historico = 'aprovado'
      )
  AND NOT EXISTS (
        SELECT 1
          FROM matricula m
          JOIN historico h ON h.id_matricula = m.id_matricula
         WHERE m.id_aluno = a.id_aluno
           AND h.situacao_historico IN ('reprovado_nota',
                                        'reprovado_falta',
                                        'reprovado_nota_falta')
      )
ORDER BY c.codigo_curso, a.nome_aluno;


-- ---------------------------------------------------------------------
-- Q5 — Taxa de aprovação por disciplina x média geral (CTE + CASE)
-- ---------------------------------------------------------------------
-- Objetivo: para cada disciplina já cursada, quantos alunos terminaram,
-- quantos aprovaram, quantos reprovaram por nota e por falta, e se a
-- taxa de aprovação está abaixo, na ou acima da média da instituição.
--
-- Técnica: duas CTEs encadeadas + CASE em dois papéis.
--   CTE "resultado": contagens por disciplina.
--   CTE "geral": lê "resultado" e calcula a taxa da instituição inteira.
--   A consulta final lê as duas como se fossem tabelas. Cada passo tem
--   nome e é lido de cima para baixo; sem CTE seriam subconsultas
--   aninhadas e a conta da taxa repetida em vários lugares.
--   CASE dentro do SUM transforma cada linha em 1 ou 0 (contagem
--   condicional). CASE no SELECT final classifica a disciplina.
--
-- Por que comparar com a média geral e não com um valor fixo (ex.: 50%):
-- uma régua fixa não diz nada se todas as disciplinas ficam acima dela.
-- A margem de 5 pontos evita rotular diferenças pequenas.
--
-- Só entra quem terminou a disciplina: 'cursando' e 'trancada' ainda
-- não têm resultado e distorceriam a taxa.
-- reprovado_nota_falta conta nas duas colunas de reprovação.
--
-- 100.0 (e não 100) força divisão decimal: inteiro / inteiro no
-- PostgreSQL trunca (3 / 4 = 0).
WITH resultado AS (
    SELECT
        t.id_disciplina,
        COUNT(*) AS concluintes,
        SUM(CASE WHEN h.situacao_historico = 'aprovado'
                 THEN 1 ELSE 0 END) AS aprovados,
        SUM(CASE WHEN h.situacao_historico IN ('reprovado_nota', 'reprovado_nota_falta')
                 THEN 1 ELSE 0 END) AS repr_nota,
        SUM(CASE WHEN h.situacao_historico IN ('reprovado_falta', 'reprovado_nota_falta')
                 THEN 1 ELSE 0 END) AS repr_falta
    FROM historico h
    JOIN matricula m ON m.id_matricula = h.id_matricula
    JOIN turma     t ON t.id_turma     = m.id_turma
    WHERE h.situacao_historico NOT IN ('cursando', 'trancada')
    GROUP BY t.id_disciplina
),
geral AS (
    SELECT 100.0 * SUM(aprovados) / SUM(concluintes) AS taxa_geral
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
JOIN disciplina d ON d.id_disciplina = r.id_disciplina
CROSS JOIN geral g
ORDER BY taxa_aprovacao, d.codigo_disciplina;


-- ---------------------------------------------------------------------
-- Q6 — Árvore de pré-requisitos de Compiladores em CCO e ECO (recursiva)
-- ---------------------------------------------------------------------
-- Objetivo: listar tudo o que precisa ser cursado antes de CMP
-- (Compiladores), direta ou indiretamente, com o nível de cada requisito,
-- em cada um dos dois currículos. A mesma disciplina tem árvores
-- diferentes: em CCO, Linguagens Formais exige Teoria da Computação; em
-- ECO, exige Estrutura de Dados. Em ECO a cadeia tem 4 níveis, a mais
-- profunda do banco.
--
-- Técnica: WITH RECURSIVE. Tem duas partes ligadas por UNION ALL:
--   âncora    -> roda uma vez: os requisitos diretos de CMP (nível 1);
--   recursiva -> roda de novo sobre as linhas que acabaram de entrar,
--                buscando os requisitos de cada requisito (nível + 1).
--   Para quando uma rodada não acha nenhuma linha nova.
--
-- id_curriculo é carregado de uma rodada para a outra e entra no JOIN da
-- parte recursiva: a árvore de CCO só desce por exigências de CCO. Sem
-- isso, os dois currículos se misturariam a partir do 2º nível.
--
-- caminho guarda os ids já visitados no ramo. A condição
-- NOT (... = ANY(caminho)) impede laço infinito se um dia alguém
-- cadastrar um ciclo (A exige B, B exige A). O CHECK do banco só
-- barra o ciclo direto A -> A, não ciclos maiores.
--
-- Só segue vínculo 'pre_requisito'. 'co_requisito' pode ser cursado no
-- mesmo semestre, então não é algo que precisa vir ANTES.
--
-- Uma disciplina pode aparecer mais de uma vez se for exigida por dois
-- ramos diferentes: é uma árvore, não uma lista de únicos.
WITH RECURSIVE arvore AS (
    -- âncora: requisitos diretos de CMP, em cada currículo
    SELECT
        pr.id_curriculo,
        pr.id_disciplina_requisito                          AS id_requisito,
        1                                                   AS nivel,
        ARRAY[pr.id_disciplina, pr.id_disciplina_requisito] AS caminho
    FROM pre_requisito pr
    JOIN disciplina d ON d.id_disciplina = pr.id_disciplina
    WHERE d.codigo_disciplina      = 'CMP'
      AND pr.vinculo_pre_requisito = 'pre_requisito'

    UNION ALL

    -- recursiva: requisitos dos requisitos, no mesmo currículo
    SELECT
        a.id_curriculo,
        pr.id_disciplina_requisito,
        a.nivel + 1,
        a.caminho || pr.id_disciplina_requisito
    FROM arvore a
    JOIN pre_requisito pr
      ON pr.id_curriculo  = a.id_curriculo
     AND pr.id_disciplina = a.id_requisito
    WHERE pr.vinculo_pre_requisito = 'pre_requisito'
      AND NOT (pr.id_disciplina_requisito = ANY (a.caminho))
)
SELECT
    c.codigo_curso,
    a.nivel,
    repeat('    ', a.nivel - 1) || d.codigo_disciplina AS requisito,
    d.nome_disciplina,
    (SELECT string_agg(dc.codigo_disciplina, ' <- ' ORDER BY x.ord)
       FROM unnest(a.caminho) WITH ORDINALITY AS x(id, ord)
       JOIN disciplina dc ON dc.id_disciplina = x.id) AS caminho
FROM arvore a
JOIN disciplina d  ON d.id_disciplina = a.id_requisito
JOIN curriculo cu  ON cu.id_curriculo = a.id_curriculo
JOIN curso c       ON c.id_curso      = cu.id_curso
ORDER BY c.codigo_curso, a.caminho;


-- ---------------------------------------------------------------------
-- Q7 — Disciplinas que um aluno já pode cursar (consulta recursiva)
-- ---------------------------------------------------------------------
-- Objetivo: para a aluna 202510007, listar as disciplinas do currículo
-- dela que ainda não foram aprovadas, não estão em curso e cujos
-- pré-requisitos já foram TODOS cumpridos.
--
-- Técnica: WITH RECURSIVE para o fecho transitivo + NOT EXISTS.
--   requisitos -> para cada disciplina, TODOS os requisitos, diretos e
--                 indiretos (se C exige B e B exige A, C exige A também);
--   cumpridas  -> disciplinas em que a aluna tem 'aprovado';
--   resultado  -> disciplina do currículo para a qual NÃO EXISTE
--                 requisito fora de "cumpridas". Disciplina sem nenhum
--                 requisito passa direto (NOT EXISTS de nada é verdade).
--
-- Por que recursivo e não só o requisito direto: olhar um nível só
-- confia que quem tem B aprovada também tem A. Isso vale num histórico
-- consistente, mas quebra com aproveitamento de estudos ou carga manual.
-- O fecho garante a regra inteira, independente de como o histórico
-- foi preenchido.
--
-- pre_requisito é por currículo: a mesma disciplina pode ter exigência
-- diferente em CCO e em ECO. Por isso a âncora só pega exigências do
-- currículo da aluna, e a parte recursiva continua nesse mesmo currículo.
--
-- Fica de fora o que está 'cursando': a aluna já está matriculada.
-- Co-requisito não bloqueia (pode cursar junto), por isso não entra.
-- NOT IN em "cumpridas" é seguro aqui: id_disciplina nunca é NULL.
WITH RECURSIVE
aluna AS (
    SELECT id_aluno, id_curriculo
    FROM aluno
    WHERE matricula_aluno = '202510007'
),
requisitos AS (
    -- âncora: requisito direto de cada disciplina do currículo da aluna
    SELECT
        pr.id_curriculo,
        pr.id_disciplina,
        pr.id_disciplina_requisito AS id_requisito,
        ARRAY[pr.id_disciplina, pr.id_disciplina_requisito] AS caminho
    FROM pre_requisito pr
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
    JOIN pre_requisito pr
      ON pr.id_curriculo  = r.id_curriculo
     AND pr.id_disciplina = r.id_requisito
    WHERE pr.vinculo_pre_requisito = 'pre_requisito'
      AND NOT (pr.id_disciplina_requisito = ANY (r.caminho))
),
historico_aluna AS (
    SELECT t.id_disciplina, h.situacao_historico
    FROM aluna al
    JOIN matricula m ON m.id_aluno     = al.id_aluno
    JOIN historico h ON h.id_matricula = m.id_matricula
    JOIN turma     t ON t.id_turma     = m.id_turma
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
JOIN curriculo_disciplina cd ON cd.id_curriculo = al.id_curriculo
JOIN disciplina d            ON d.id_disciplina = cd.id_disciplina
WHERE NOT EXISTS (                       -- ainda não aprovada
        SELECT 1 FROM cumpridas c
         WHERE c.id_disciplina = cd.id_disciplina)
  AND NOT EXISTS (                       -- não está cursando agora
        SELECT 1 FROM historico_aluna ha
         WHERE ha.id_disciplina = cd.id_disciplina
           AND ha.situacao_historico = 'cursando')
  AND NOT EXISTS (                       -- nenhum requisito pendente
        SELECT 1 FROM requisitos r
         WHERE r.id_disciplina = cd.id_disciplina
           AND r.id_requisito NOT IN (SELECT id_disciplina FROM cumpridas))
ORDER BY cd.periodo_curriculo_disciplina, d.codigo_disciplina;


-- ---------------------------------------------------------------------
-- Q8 — Cada aluno x a própria turma (função de janela de agregação)
-- ---------------------------------------------------------------------
-- Objetivo: na turma CCODM2A-ED (Estrutura de Dados, 2026/1), mostrar a
-- média final de cada aluno ao lado da média, da maior e da menor nota
-- da turma, e quanto o aluno ficou acima ou abaixo da média.
--
-- Técnica: AVG/MAX/MIN com OVER (PARTITION BY ...).
--   GROUP BY junta as linhas e devolve UMA por grupo: a média da turma
--   apareceria, mas o aluno sumiria.
--   A função de janela calcula o mesmo agregado sobre o grupo (a
--   "janela") e repete o valor em CADA linha, sem juntar nada. Assim
--   o dado individual e o do grupo ficam lado a lado.
--   PARTITION BY m.id_turma define a janela: cada turma é um grupo.
--   A WINDOW turma_w nomeia a janela uma vez e evita repetir o OVER.
--
-- Só entra quem tem média final: trancada e cursando têm média NULL
-- (ausência de nota não é zero) e distorceriam a média da turma.
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
FROM historico h
JOIN matricula m ON m.id_matricula = h.id_matricula
JOIN aluno     a ON a.id_aluno     = m.id_aluno
JOIN turma     t ON t.id_turma     = m.id_turma
WHERE t.codigo_turma = 'CCODM2A-ED'
  AND h.media_final_historico IS NOT NULL
WINDOW turma_w AS (PARTITION BY m.id_turma)
ORDER BY diferenca DESC;


-- ---------------------------------------------------------------------
-- Q9 — Ranking e percentil dos alunos dentro do curso (janela)
-- ---------------------------------------------------------------------
-- Objetivo: ordenar os alunos de cada curso pela média geral (média
-- das médias finais das disciplinas já encerradas) e mostrar a posição,
-- o percentil e o quartil de cada um. Lista o top 10 de cada curso.
--
-- Técnica: funções de janela de ranking com
-- OVER (PARTITION BY curso ORDER BY média DESC).
--   PARTITION BY id_curso -> CCO e ECO são rankeados separadamente;
--   ORDER BY média DESC   -> define quem vem primeiro.
--   RANK()         -> posição; empate divide a posição e PULA a seguinte
--                     (1, 2, 2, 4).
--   DENSE_RANK()   -> igual, mas NÃO pula (1, 2, 2, 3).
--   PERCENT_RANK() -> (rank - 1) / (total - 1): 0 = melhor, 1 = pior.
--                     Aqui exibido como "à frente de X% do curso".
--   NTILE(4)       -> divide o curso em 4 faixas de tamanho igual
--                     (quartil 1 = 25% melhores).
--
-- Por que duas CTEs e o filtro de top 10 fora: função de janela é
-- calculada DEPOIS do WHERE. Não dá para escrever WHERE posicao <= 10
-- na mesma consulta em que o RANK é calculado; o filtro vai num nível
-- de fora.
--
-- percentile_cont NÃO serve aqui: é agregação (WITHIN GROUP), devolve
-- UM valor por grupo (ex.: a nota mediana do curso), não a posição de
-- cada aluno.
WITH media_aluno AS (
    SELECT
        a.id_aluno,
        a.id_curso,
        a.matricula_aluno,
        a.nome_aluno,
        ROUND(AVG(h.media_final_historico), 2) AS media_geral
    FROM aluno a
    JOIN matricula m ON m.id_aluno     = a.id_aluno
    JOIN historico h ON h.id_matricula = m.id_matricula
    WHERE h.media_final_historico IS NOT NULL
      AND h.situacao_historico NOT IN ('cursando', 'trancada')
    GROUP BY a.id_aluno
),
ranking AS (
    SELECT
        ma.*,
        RANK()       OVER curso_w AS posicao,
        DENSE_RANK() OVER curso_w AS posicao_densa,
        ROUND((1 - PERCENT_RANK() OVER curso_w)::numeric * 100, 1) AS a_frente_de_pct,
        NTILE(4)     OVER curso_w AS quartil
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
JOIN curso c ON c.id_curso = r.id_curso
WHERE r.posicao <= 10
ORDER BY c.codigo_curso, r.posicao, r.nome_aluno;


-- ---------------------------------------------------------------------
-- Q10 — Evolução do rendimento semestre a semestre (janela com LAG)
-- ---------------------------------------------------------------------
-- Objetivo: para cada aluno, a média do semestre comparada com a média
-- do semestre anterior: quanto subiu ou caiu e a tendência. Exibe duas
-- trajetórias opostas: a 1ª colocada de CCO na Q9 (202510003) e a aluna
-- com mais reprovações, usada na Q7 (202510007).
--
-- Técnica: LAG() OVER (PARTITION BY aluno ORDER BY ano, semestre).
--   LAG(x) devolve o valor de x na linha ANTERIOR da janela, sem
--   self-join. PARTITION BY id_aluno faz cada aluno ter sua própria
--   sequência; ORDER BY ano, semestre define o que é "anterior".
--   Sem o ORDER BY, "anterior" não teria significado.
--   FIRST_VALUE() pega o primeiro semestre da mesma janela, para medir
--   a evolução acumulada desde o ingresso.
--
-- O primeiro semestre de cada aluno não tem anterior: LAG devolve NULL
-- e a variação fica NULL. É o esperado, não um erro; o CASE trata como
-- 'início'.
--
-- A CTE agrega primeiro (uma linha por aluno e semestre) e só depois a
-- janela compara as linhas. 2026/2 fica de fora: ainda está em curso e
-- não tem média final.
WITH media_semestre AS (
    SELECT
        a.id_aluno,
        a.matricula_aluno,
        a.nome_aluno,
        pl.ano_periodo_letivo                  AS ano,
        pl.semestre_periodo_letivo             AS semestre,
        ROUND(AVG(h.media_final_historico), 2) AS media
    FROM aluno a
    JOIN matricula      m  ON m.id_aluno           = a.id_aluno
    JOIN historico      h  ON h.id_matricula       = m.id_matricula
    JOIN turma          t  ON t.id_turma           = m.id_turma
    JOIN periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
    WHERE h.media_final_historico IS NOT NULL
      AND h.situacao_historico NOT IN ('cursando', 'trancada')
    GROUP BY a.id_aluno, pl.ano_periodo_letivo, pl.semestre_periodo_letivo
),
evolucao AS (
    SELECT
        ms.*,
        LAG(ms.media)         OVER aluno_w AS media_anterior,
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
        WHEN e.variacao IS NULL THEN 'início'
        WHEN e.variacao > 0     THEN 'subiu'
        WHEN e.variacao < 0     THEN 'caiu'
        ELSE 'estável'
    END AS tendencia
FROM evolucao e
WHERE e.matricula_aluno IN ('202510003', '202510007')
ORDER BY e.matricula_aluno, e.ano, e.semestre;
