#!/usr/bin/env bash
# Mede cada índice de desempenho de sql/01_ddl.sql (Parte 3) com EXPLAIN (ANALYZE, BUFFERS),
# antes e depois, e gera evidencias/explain.md com os dados da execução.
#
# Uso, a partir da raiz do projeto (depois de rodar 01 e 02):
#   bash scripts/evidencias_explain.sh
#
# Variáveis opcionais:
#   N_EXEC=11            execuções por medição (o tempo registrado é a mediana)
#   PG_CONTAINER=nome    usa "docker exec" nesse container em vez do compose
#
# Como o "antes" é medido sem mexer no banco:
#   BEGIN; DROP INDEX ...; EXPLAIN ...; ROLLBACK;
# O DROP só vale dentro da transação. O ROLLBACK devolve o índice intacto.
# Durante esses milissegundos a tabela fica com bloqueio exclusivo, então não
# rode isto com o sistema em uso.

set -euo pipefail
cd "$(dirname "$0")/.."
export LC_NUMERIC=C   # awk com ponto decimal, igual à saída do Postgres

ARQ="evidencias/explain.md"
N_EXEC="${N_EXEC:-11}"
if [ -n "${PG_CONTAINER:-}" ]; then
    PSQL=(docker exec -i "$PG_CONTAINER" psql -X -q -At -v ON_ERROR_STOP=1 -U bd2 -d matricula)
else
    PSQL=(docker compose exec -T postgres psql -X -q -At -v ON_ERROR_STOP=1 -U bd2 -d matricula)
fi
mkdir -p evidencias

INDICES=(ix_matricula_turma ix_log_matricula_matricula ix_log_matricula_excecao ix_log_matricula_detalhe)

# ---------------------------------------------------------------------
# 0. Pré-condições
# ---------------------------------------------------------------------
LISTA=$(printf "'%s'," "${INDICES[@]}"); LISTA="${LISTA%,}"
TEM=$("${PSQL[@]}" -c "SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname IN ($LISTA)")
if [ "$TEM" != "${#INDICES[@]}" ]; then
    echo "Os índices de desempenho de sql/01_ddl.sql não estão no banco ($TEM de ${#INDICES[@]})."
    echo "O banco foi criado com uma versão antiga do 01? Recomece do zero (EXECUTE.md, seção 4)."
    exit 1
fi

# Valores usados nas consultas, lidos do banco (ids são gerados na carga).
ID_TURMA=$("${PSQL[@]}" -c "
    SELECT t.id_turma FROM tb_turma t
      JOIN tb_periodo_letivo pl USING (id_periodo_letivo)
     WHERE t.codigo_turma = 'CCODM2B-BD2'
       AND pl.ano_periodo_letivo = 2026 AND pl.semestre_periodo_letivo = 2")
ID_MAT=$("${PSQL[@]}" -c "
    SELECT min(id_matricula) FROM tb_log_matricula WHERE acao_log_matricula = 'trancada'")
if [ -z "$ID_TURMA" ] || [ -z "$ID_MAT" ]; then
    echo "Não achei a turma CCODM2B-BD2 de 2026/2 ou uma matrícula trancada no log."
    echo "A carga (sql/02_carga.sql) foi rodada?"
    exit 1
fi

# ---------------------------------------------------------------------
# 1. Consultas medidas (uma por índice, mesma ordem de INDICES)
# ---------------------------------------------------------------------
CONSULTAS=(
"SELECT count(*)
  FROM tb_matricula
 WHERE id_turma = $ID_TURMA
   AND status_matricula IN ('ativa', 'concluida')
   AND id_matricula <> 0;"
"SELECT *
  FROM tb_log_matricula
 WHERE id_matricula = $ID_MAT
 ORDER BY ocorrido_em_log_matricula;"
"SELECT *
  FROM tb_log_matricula
 WHERE acao_log_matricula <> 'criada'
 ORDER BY ocorrido_em_log_matricula DESC
 LIMIT 20;"
"SELECT *
  FROM tb_log_matricula
 WHERE detalhe_log_matricula @> '{\"id_turma\": $ID_TURMA}';"
)

TITULOS=(
"Vagas ocupadas de uma turma (contagem da trigger de vagas)"
"Trilha de auditoria de uma matrícula"
"Eventos de exceção mais recentes (índice parcial)"
"Eventos de uma turma dentro do jsonb (GIN)"
)

# Textos fixos: explicam o mecanismo. Os números ficam só nas tabelas geradas.
read_texto() { cat; }
PARA_QUE=(
"$(read_texto <<'TXT'
É a contagem que a trigger `trg_verifica_vaga` (`sql/06b_regra_vagas.sql`) faz a
cada matrícula, na turma `CCODM2B-BD2` de 2026/2, a mesma da disputa pela última
vaga do `06_transacoes.sql`. O `id_matricula <> 0` faz o papel de
`NEW.id_matricula` (a trigger não conta a própria linha).
TXT
)"
"$(read_texto <<'TXT'
Tudo o que aconteceu com uma matrícula, em ordem. A matrícula medida é a primeira
que tem um trancamento no log, então tem mais de um evento.
TXT
)"
"$(read_texto <<'TXT'
Os trancamentos e remoções mais recentes, que é o que a coordenação audita. O
`WHERE` da consulta é o mesmo do índice parcial: é isso que permite ao
planejador usar o índice.
TXT
)"
"$(read_texto <<'TXT'
Todos os eventos de matrícula da turma `CCODM2B-BD2`. O log não tem coluna
`id_turma`: o dado está dentro de `detalhe_log_matricula` (jsonb), e só um GIN
consegue indexar o conteúdo do jsonb.
TXT
)"
)

POR_QUE=(
"$(read_texto <<'TXT'
Sem o índice, o Postgres lê todas as páginas de `tb_matricula` (matrículas de
todos os semestres) e descarta as que não são da turma. Com o índice, ele acha
direto as cerca de 40 entradas da turma e só visita as páginas onde elas estão
(Bitmap Heap Scan). O custo deixa de depender do tamanho da tabela e passa a
depender do tamanho da turma.

O ganho que mais importa aqui não é o tempo da consulta isolada: a trigger faz
essa contagem **segurando o `FOR UPDATE` da turma**. Contagem mais curta
significa bloqueio mais curto e menos espera na disputa pela última vaga.
Sem o índice, esse tempo cresceria a cada semestre de histórico acumulado.
TXT
)"
"$(read_texto <<'TXT'
Sem o índice, o Postgres lê o log inteiro, que é a maior tabela do banco em
páginas, para achar um ou dois eventos, e ainda ordena o resultado. Com o
índice em `(id_matricula, ocorrido_em_log_matricula)`, ele desce a árvore até a
matrícula e lê as entradas já na ordem da segunda coluna: o nó `Sort` some do
plano. O log só cresce, então o Seq Scan só pioraria com o tempo.
TXT
)"
"$(read_texto <<'TXT'
Sem o índice, o Postgres lê o log inteiro, filtra os poucos eventos que não são
`criada` e ordena tudo para devolver 20. Com o índice parcial, que só contém
esses eventos já na ordem `DESC`, ele lê as 20 primeiras entradas e para: não há
`Sort`, e o `Limit` interrompe a leitura.

O índice parcial também quase não custa nada: guarda só os eventos de exceção,
e o `INSERT` de um evento `criada`, que é o caso comum, nem toca nele, porque a
linha não satisfaz o `WHERE` do índice.
TXT
)"
"$(read_texto <<'TXT'
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
TXT
)"
)

# ---------------------------------------------------------------------
# 2. Medição
# ---------------------------------------------------------------------
# pg_temp.medir roda a consulta 1 vez para aquecer o cache e depois N vezes
# com EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON). Devolve, numa linha:
#   nós de leitura | buffers do nó raiz (hit + read) | mediana do Execution Time
# O nó raiz soma os buffers dos filhos, então é o total da consulta.
read -r -d '' FUNCAO <<'SQL' || true
CREATE FUNCTION pg_temp.medir(q text, n int) RETURNS text
LANGUAGE plpgsql AS $f$
DECLARE
    p      jsonb;
    tempos numeric[] := '{}';
    acesso text;
BEGIN
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || q INTO p;   -- aquecimento
    FOR i IN 1..n LOOP
        EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || q INTO p;
        tempos := tempos || (p->0->>'Execution Time')::numeric;
    END LOOP;

    SELECT string_agg(no->>'Node Type'
                      || coalesce(' em ' || (no->>'Relation Name'), '')
                      || coalesce(' usando ' || (no->>'Index Name'), ''), ' + ')
      INTO acesso
      FROM jsonb_path_query(p, 'strict $.**') AS no
     WHERE jsonb_typeof(no) = 'object'
       AND no->>'Node Type' LIKE '%Scan%';

    RETURN acesso
        || '|' || ((p->0->'Plan'->>'Shared Hit Blocks')::int
                 + (p->0->'Plan'->>'Shared Read Blocks')::int)
        || '|' || (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY t)::numeric, 3)
                     FROM unnest(tempos) t);
END
$f$;
SQL

# medir <indice> <consulta> <antes|depois>
# Saída: 1ª linha = métricas; resto = EXPLAIN (ANALYZE, BUFFERS) em texto.
medir() {
    local drop=""
    [ "$3" = "antes" ] && drop="DROP INDEX $1;"
    "${PSQL[@]}" <<SQL
BEGIN;
$drop
$FUNCAO
SELECT pg_temp.medir(\$q\$$2\$q\$, $N_EXEC);
EXPLAIN (ANALYZE, BUFFERS) $2
ROLLBACK;
SQL
}

declare -a RESUMO
TODOS_USAM=sim
SECOES=""
for i in "${!INDICES[@]}"; do
    ix="${INDICES[$i]}"; q="${CONSULTAS[$i]}"
    echo "Medindo $ix..."

    SAIDA_A=$(medir "$ix" "$q" antes)
    SAIDA_D=$(medir "$ix" "$q" depois)
    IFS='|' read -r acesso_a buf_a ms_a <<< "$(head -n 1 <<< "$SAIDA_A")"
    IFS='|' read -r acesso_d buf_d ms_d <<< "$(head -n 1 <<< "$SAIDA_D")"
    PLANO_A=$(tail -n +2 <<< "$SAIDA_A")
    PLANO_D=$(tail -n +2 <<< "$SAIDA_D")

    INFO=$("${PSQL[@]}" -c "
        SELECT indexdef || '|' || pg_size_pretty(pg_relation_size(indexname::regclass))
          FROM pg_indexes WHERE schemaname = 'public' AND indexname = '$ix'")
    DEF="${INFO%|*}"; TAM="${INFO##*|}"

    RED_BUF=$(awk -v a="$buf_a" -v d="$buf_d" 'BEGIN { printf "%.0f", (1 - d / a) * 100 }')
    FATOR=$(awk -v a="$ms_a" -v d="$ms_d" 'BEGIN { if (d > 0) printf "%.1f", a / d; else print "—" }')
    case "$acesso_d" in *"usando $ix"*) ;; *) TODOS_USAM=nao ;; esac

    RESUMO+=("| \`$ix\` | ${TITULOS[$i]} | $buf_a → $buf_d (−$RED_BUF%) | $ms_a → $ms_d (${FATOR}×) | $TAM |")

    SECOES+="
### $((i + 1)). \`$ix\`

**Definição** ($TAM):

\`\`\`sql
$DEF;
\`\`\`

**Consulta testada:** ${TITULOS[$i]}.

${PARA_QUE[$i]}

\`\`\`sql
$q
\`\`\`

**Antes (sem o índice):**

\`\`\`text
$PLANO_A
\`\`\`

**Depois (com o índice):**

\`\`\`text
$PLANO_D
\`\`\`

**Ganho medido:**

| Medida | Antes | Depois |
|---|---|---|
| Leitura | $acesso_a | $acesso_d |
| Buffers (páginas de 8 kB) | $buf_a | $buf_d |
| Tempo de execução (mediana de $N_EXEC) | $ms_a ms | $ms_d ms |

Páginas lidas: −$RED_BUF%. Tempo: ${FATOR}× mais rápido.

**Por que ganhou:**

${POR_QUE[$i]}

---
"
done

# ---------------------------------------------------------------------
# 3. Relatório
# ---------------------------------------------------------------------
VERSAO=$("${PSQL[@]}" -c "SELECT split_part(version(), ' ', 2)")
TAMANHOS=$("${PSQL[@]}" -c "
    SELECT format('| \`%s\` | %s | %s |', c.relname, c.relpages,
                  c.reltuples::bigint)
      FROM pg_class c
     WHERE c.relname IN ('tb_matricula', 'tb_log_matricula')
     ORDER BY c.relname")
DATA=$(date '+%d/%m/%Y %H:%M')

{
cat <<EOF
# Evidências: índices e EXPLAIN (ANALYZE, BUFFERS)

**Frente:** Modelagem Física e Desempenho · Banco de Dados II (CCO072) · IESB 2026/2
**Scripts:** \`sql/01_ddl.sql\`, Parte 3 (índices) e \`scripts/evidencias_explain.sh\` (este relatório)
**Gerado em:** $DATA
**PostgreSQL:** $VERSAO (Docker, banco \`matricula\`)

## Resumo

| Índice | Consulta | Buffers antes → depois | Tempo (ms) antes → depois | Tamanho |
|---|---|---|---|---|
EOF
printf '%s\n' "${RESUMO[@]}"
cat <<'EOF'

São 4 índices: dois B-tree comuns, um B-tree **parcial**
(`ix_log_matricula_excecao`) e um **GIN em jsonb** (`ix_log_matricula_detalhe`).
Nenhum plano foi forçado: não há `enable_seqscan = off` nem outro ajuste.
EOF
if [ "$TODOS_USAM" = sim ]; then
    echo "Nesta execução, o planejador escolheu sozinho o índice em todas as consultas."
else
    echo "**Atenção:** nesta execução, o planejador não usou o índice em pelo menos uma"
    echo "consulta. Veja a linha \"Leitura\" de cada seção."
fi
cat <<'EOF'

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
EOF
printf '%s\n' "$TAMANHOS"
cat <<'EOF'

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
EOF
printf '%s\n' "$SECOES"
} > "$ARQ"

echo "Relatório gerado em $ARQ"
