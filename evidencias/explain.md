# Evidências: índices e EXPLAIN (ANALYZE, BUFFERS)

**Frente:** Modelagem Física e Desempenho · Banco de Dados II (CCO072) · IESB 2026/2
**Scripts:** `sql/01_ddl.sql`, Parte 3 (índices) e `scripts/evidencias_explain.sh` (este relatório)
**Gerado em:** 10/11/2026 17:11
**PostgreSQL:** 17.11 (Docker, banco `matricula`)

## Resumo

| Índice | Consulta | Buffers antes → depois | Tempo (ms) antes → depois | Tamanho |
|---|---|---|---|---|
| `ix_matricula_turma` | Vagas ocupadas de uma turma (contagem da trigger de vagas) | 25 → 12 (−52%) | 0.173 → 0.016 (10.8×) | 56 kB |
| `ix_log_matricula_matricula` | Trilha de auditoria de uma matrícula | 91 → 3 (−97%) | 0.122 → 0.006 (20.3×) | 120 kB |
| `ix_log_matricula_excecao` | Eventos de exceção mais recentes (índice parcial) | 91 → 21 (−77%) | 0.148 → 0.007 (21.1×) | 16 kB |
| `ix_log_matricula_detalhe` | Eventos de uma turma dentro do jsonb (GIN) | 91 → 34 (−63%) | 0.797 → 0.023 (34.7×) | 64 kB |

São 4 índices: dois B-tree comuns, um B-tree **parcial**
(`ix_log_matricula_excecao`) e um **GIN em jsonb** (`ix_log_matricula_detalhe`).
Nenhum plano foi forçado: não há `enable_seqscan = off` nem outro ajuste.
Nesta execução, o planejador escolheu sozinho o índice em todas as consultas.

## Como foi medido

- **Antes:** `BEGIN; DROP INDEX ...; EXPLAIN ...; ROLLBACK;`. O índice some só
  dentro da transação, e o `ROLLBACK` o devolve. O banco não é alterado.
- **Depois:** a mesma consulta, com o índice no lugar.
- Cada consulta roda uma vez para aquecer o cache e depois várias vezes com
  `EXPLAIN (ANALYZE, BUFFERS)`. O tempo registrado é a **mediana** dessas
  execuções. O plano mostrado abaixo é de uma execução a mais.
- **Buffers** é o total de páginas de 8 kB que a consulta tocou (`shared hit` +
  `shared read`), lido do nó raiz do plano, que soma os filhos.

## Limites desta medição

As tabelas são pequenas e cabem inteiras na memória:

| Tabela | Páginas | Linhas |
|---|---|---|
| `tb_log_matricula` | 91 | 3354 |
| `tb_matricula` | 25 | 3320 |

Por isso os tempos ficam abaixo de 1 ms e variam de uma execução para outra.
A medida mais estável é **buffers**: ela não depende da máquina nem do cache, e
mostra quanto trabalho cada plano faz. O Seq Scan lê todas as páginas, então
seu custo cresce com a tabela. O acesso por índice depende só de quantas linhas
a consulta devolve. Com mais semestres de matrículas e mais eventos no log, a
diferença aumenta.

Índice também tem custo: espaço em disco e uma escrita a mais em cada `INSERT`
(e em `UPDATE` da coluna indexada). Os quatro estão em tabelas em que leitura
seletiva é frequente. O parcial evita até esse custo no caso comum, como
explicado na seção 3.

## Índices

### 1. `ix_matricula_turma`

**Definição** (56 kB):

```sql
CREATE INDEX ix_matricula_turma ON public.tb_matricula USING btree (id_turma);
```

**Consulta testada:** Vagas ocupadas de uma turma (contagem da trigger de vagas).

É a contagem que a trigger `trg_verifica_vaga` (`sql/06b_regra_vagas.sql`) faz a
cada matrícula, na turma `CCODM2B-BD2` de 2026/2, a mesma da disputa pela última
vaga do `06_transacoes.sql`. O `id_matricula <> 0` faz o papel de
`NEW.id_matricula` (a trigger não conta a própria linha).

```sql
SELECT count(*)
  FROM tb_matricula
 WHERE id_turma = 73
   AND status_matricula IN ('ativa', 'concluida')
   AND id_matricula <> 0;
```

**Antes (sem o índice):**

```text
Aggregate  (cost=83.20..83.21 rows=1 width=8) (actual time=0.387..0.388 rows=1 loops=1)
  Buffers: shared hit=25
  ->  Seq Scan on tb_matricula  (cost=0.00..83.10 rows=40 width=0) (actual time=0.011..0.382 rows=40 loops=1)
        Filter: ((status_matricula = ANY ('{ativa,concluida}'::status_mat_t[])) AND (id_matricula <> 0) AND (id_turma = 73))
        Rows Removed by Filter: 3280
        Buffers: shared hit=25
Planning Time: 0.058 ms
Execution Time: 0.401 ms
```

**Depois (com o índice):**

```text
Aggregate  (cost=31.21..31.22 rows=1 width=8) (actual time=0.048..0.049 rows=1 loops=1)
  Buffers: shared hit=12
  ->  Bitmap Heap Scan on tb_matricula  (cost=4.59..31.11 rows=40 width=0) (actual time=0.027..0.043 rows=40 loops=1)
        Recheck Cond: (id_turma = 73)
        Filter: ((status_matricula = ANY ('{ativa,concluida}'::status_mat_t[])) AND (id_matricula <> 0))
        Heap Blocks: exact=10
        Buffers: shared hit=12
        ->  Bitmap Index Scan on ix_matricula_turma  (cost=0.00..4.58 rows=40 width=0) (actual time=0.016..0.016 rows=45 loops=1)
              Index Cond: (id_turma = 73)
              Buffers: shared hit=2
Planning Time: 0.069 ms
Execution Time: 0.066 ms
```

**Ganho medido:**

| Medida | Antes | Depois |
|---|---|---|
| Leitura | Seq Scan em tb_matricula | Bitmap Heap Scan em tb_matricula + Bitmap Index Scan usando ix_matricula_turma |
| Buffers (páginas de 8 kB) | 25 | 12 |
| Tempo de execução (mediana de 11) | 0.173 ms | 0.016 ms |

Páginas lidas: −52%. Tempo: 10.8× mais rápido.

**Por que ganhou:**

Sem o índice, o Postgres lê todas as páginas de `tb_matricula` (matrículas de
todos os semestres) e descarta as que não são da turma. Com o índice, ele acha
direto as cerca de 40 entradas da turma e só visita as páginas onde elas estão
(Bitmap Heap Scan). O custo deixa de depender do tamanho da tabela e passa a
depender do tamanho da turma.

O ganho que mais importa aqui não é o tempo da consulta isolada: a trigger faz
essa contagem **segurando o `FOR UPDATE` da turma**. Contagem mais curta
significa bloqueio mais curto e menos espera na disputa pela última vaga.
Sem o índice, esse tempo cresceria a cada semestre de histórico acumulado.

---

### 2. `ix_log_matricula_matricula`

**Definição** (120 kB):

```sql
CREATE INDEX ix_log_matricula_matricula ON public.tb_log_matricula USING btree (id_matricula, ocorrido_em_log_matricula);
```

**Consulta testada:** Trilha de auditoria de uma matrícula.

Tudo o que aconteceu com uma matrícula, em ordem. A matrícula medida é a primeira
que tem um trancamento no log, então tem mais de um evento.

```sql
SELECT *
  FROM tb_log_matricula
 WHERE id_matricula = 7
 ORDER BY ocorrido_em_log_matricula;
```

**Antes (sem o índice):**

```text
Sort  (cost=132.94..132.94 rows=2 width=183) (actual time=0.116..0.116 rows=2 loops=1)
  Sort Key: ocorrido_em_log_matricula
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=91
  ->  Seq Scan on tb_log_matricula  (cost=0.00..132.93 rows=2 width=183) (actual time=0.003..0.114 rows=2 loops=1)
        Filter: (id_matricula = 7)
        Rows Removed by Filter: 3352
        Buffers: shared hit=91
Planning Time: 0.018 ms
Execution Time: 0.122 ms
```

**Depois (com o índice):**

```text
Index Scan using ix_log_matricula_matricula on tb_log_matricula  (cost=0.28..10.06 rows=2 width=183) (actual time=0.002..0.003 rows=2 loops=1)
  Index Cond: (id_matricula = 7)
  Buffers: shared hit=3
Planning Time: 0.024 ms
Execution Time: 0.007 ms
```

**Ganho medido:**

| Medida | Antes | Depois |
|---|---|---|
| Leitura | Seq Scan em tb_log_matricula | Index Scan em tb_log_matricula usando ix_log_matricula_matricula |
| Buffers (páginas de 8 kB) | 91 | 3 |
| Tempo de execução (mediana de 11) | 0.122 ms | 0.006 ms |

Páginas lidas: −97%. Tempo: 20.3× mais rápido.

**Por que ganhou:**

Sem o índice, o Postgres lê o log inteiro, que é a maior tabela do banco em
páginas, para achar um ou dois eventos, e ainda ordena o resultado. Com o
índice em `(id_matricula, ocorrido_em_log_matricula)`, ele desce a árvore até a
matrícula e lê as entradas já na ordem da segunda coluna: o nó `Sort` some do
plano. O log só cresce, então o Seq Scan só pioraria com o tempo.

---

### 3. `ix_log_matricula_excecao`

**Definição** (16 kB):

```sql
CREATE INDEX ix_log_matricula_excecao ON public.tb_log_matricula USING btree (ocorrido_em_log_matricula DESC) WHERE ((acao_log_matricula)::text <> 'criada'::text);
```

**Consulta testada:** Eventos de exceção mais recentes (índice parcial).

Os trancamentos e remoções mais recentes, que é o que a coordenação audita. O
`WHERE` da consulta é o mesmo do índice parcial: é isso que permite ao
planejador usar o índice.

```sql
SELECT *
  FROM tb_log_matricula
 WHERE acao_log_matricula <> 'criada'
 ORDER BY ocorrido_em_log_matricula DESC
 LIMIT 20;
```

**Antes (sem o índice):**

```text
Limit  (cost=133.79..133.84 rows=20 width=183) (actual time=0.147..0.148 rows=20 loops=1)
  Buffers: shared hit=91
  ->  Sort  (cost=133.79..133.87 rows=34 width=183) (actual time=0.146..0.147 rows=20 loops=1)
        Sort Key: ocorrido_em_log_matricula DESC
        Sort Method: quicksort  Memory: 33kB
        Buffers: shared hit=91
        ->  Seq Scan on tb_log_matricula  (cost=0.00..132.93 rows=34 width=183) (actual time=0.003..0.142 rows=34 loops=1)
              Filter: ((acao_log_matricula)::text <> 'criada'::text)
              Rows Removed by Filter: 3320
              Buffers: shared hit=91
Planning Time: 0.023 ms
Execution Time: 0.153 ms
```

**Depois (com o índice):**

```text
Limit  (cost=0.14..73.30 rows=20 width=183) (actual time=0.003..0.008 rows=20 loops=1)
  Buffers: shared hit=21
  ->  Index Scan using ix_log_matricula_excecao on tb_log_matricula  (cost=0.14..124.52 rows=34 width=183) (actual time=0.002..0.007 rows=20 loops=1)
        Buffers: shared hit=21
Planning Time: 0.026 ms
Execution Time: 0.013 ms
```

**Ganho medido:**

| Medida | Antes | Depois |
|---|---|---|
| Leitura | Seq Scan em tb_log_matricula | Index Scan em tb_log_matricula usando ix_log_matricula_excecao |
| Buffers (páginas de 8 kB) | 91 | 21 |
| Tempo de execução (mediana de 11) | 0.148 ms | 0.007 ms |

Páginas lidas: −77%. Tempo: 21.1× mais rápido.

**Por que ganhou:**

Sem o índice, o Postgres lê o log inteiro, filtra os poucos eventos que não são
`criada` e ordena tudo para devolver 20. Com o índice parcial, que só contém
esses eventos já na ordem `DESC`, ele lê as 20 primeiras entradas e para: não há
`Sort`, e o `Limit` interrompe a leitura.

O índice parcial também quase não custa nada: guarda só os eventos de exceção,
e o `INSERT` de um evento `criada`, que é o caso comum, nem toca nele, porque a
linha não satisfaz o `WHERE` do índice.

---

### 4. `ix_log_matricula_detalhe`

**Definição** (64 kB):

```sql
CREATE INDEX ix_log_matricula_detalhe ON public.tb_log_matricula USING gin (detalhe_log_matricula jsonb_path_ops) WITH (fastupdate=off);
```

**Consulta testada:** Eventos de uma turma dentro do jsonb (GIN).

Todos os eventos de matrícula da turma `CCODM2B-BD2`. O log não tem coluna
`id_turma`: o dado está dentro de `detalhe_log_matricula` (jsonb), e só um GIN
consegue indexar o conteúdo do jsonb.

```sql
SELECT *
  FROM tb_log_matricula
 WHERE detalhe_log_matricula @> '{"id_turma": 73}';
```

**Antes (sem o índice):**

```text
Seq Scan on tb_log_matricula  (cost=0.00..132.93 rows=34 width=183) (actual time=0.013..0.839 rows=40 loops=1)
  Filter: (detalhe_log_matricula @> '{"id_turma": 73}'::jsonb)
  Rows Removed by Filter: 3314
  Buffers: shared hit=91
Planning Time: 0.051 ms
Execution Time: 0.853 ms
```

**Depois (com o índice):**

```text
Bitmap Heap Scan on tb_log_matricula  (cost=8.73..76.04 rows=34 width=183) (actual time=0.008..0.022 rows=40 loops=1)
  Recheck Cond: (detalhe_log_matricula @> '{"id_turma": 73}'::jsonb)
  Heap Blocks: exact=31
  Buffers: shared hit=34
  ->  Bitmap Index Scan on ix_log_matricula_detalhe  (cost=0.00..8.72 rows=34 width=0) (actual time=0.004..0.004 rows=40 loops=1)
        Index Cond: (detalhe_log_matricula @> '{"id_turma": 73}'::jsonb)
        Buffers: shared hit=3
Planning:
  Buffers: shared hit=1
Planning Time: 0.028 ms
Execution Time: 0.027 ms
```

**Ganho medido:**

| Medida | Antes | Depois |
|---|---|---|
| Leitura | Seq Scan em tb_log_matricula | Bitmap Heap Scan em tb_log_matricula + Bitmap Index Scan usando ix_log_matricula_detalhe |
| Buffers (páginas de 8 kB) | 91 | 34 |
| Tempo de execução (mediana de 11) | 0.797 ms | 0.023 ms |

Páginas lidas: −63%. Tempo: 34.7× mais rápido.

**Por que ganhou:**

Sem o índice, o Postgres abre o jsonb de cada linha do log para testar o `@>`.
O GIN guarda cada par chave/valor do jsonb apontando para as linhas que o
contêm, então o Bitmap Index Scan devolve só as linhas da turma, e o Postgres
visita apenas as páginas onde elas estão.

Aqui a redução de páginas é a menor dos quatro: as linhas de uma turma estão
espalhadas por muitas páginas do log (a carga insere aluno por aluno), e o
Bitmap Heap Scan precisa visitar cada uma delas. O tempo, por outro lado, cai
muito, porque o Seq Scan gasta CPU testando o `@>` no jsonb de cada linha do
log, e o índice evita esse teste em quase todas.

Usei `jsonb_path_ops`, que gera um índice menor que o opclass padrão e atende o
`@>`, o único operador usado.

---

