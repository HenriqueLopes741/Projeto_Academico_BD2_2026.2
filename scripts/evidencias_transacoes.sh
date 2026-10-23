#!/usr/bin/env bash
# Executa sql/06_transacoes.sql e gera evidencias/transacoes.md com os dados
# reais da execução. As tabelas em Markdown são montadas pelo próprio SQL.
#
# Uso, a partir da raiz do projeto:
#   bash scripts/evidencias_transacoes.sh

set -uo pipefail
cd "$(dirname "$0")/.."

ARQ="evidencias/transacoes.md"
PSQL=(docker compose exec -T postgres psql -U bd2 -d matricula)
mkdir -p evidencias

# 1. Executa o cenário (mesmo comando do EXECUTE.md) e guarda a saída bruta.
SAIDA=$("${PSQL[@]}" < ./sql/06_transacoes.sql 2>&1)
if [ $? -ne 0 ]; then
    echo "Falha ao executar sql/06_transacoes.sql. Saída:"
    echo "$SAIDA"
    exit 1
fi
if grep -q '^ERROR:' <<< "$SAIDA"; then
    echo "Atenção: a execução teve erros. Confira $ARQ e a saída bruta."
fi

# 2. Metadados da execução.
VERSAO=$("${PSQL[@]}" -At -c "SELECT split_part(version(), ' ', 2)")
DATA=$(date '+%d/%m/%Y %H:%M')

# 3. Tabelas em Markdown. Cada linha é montada no SQL com format(), então a
#    saída já sai com barras verticais, que é o que o Markdown renderiza.
#    \pset tuples_only e \pset format unaligned tiram cabeçalhos e alinhamento.
TABELAS=$("${PSQL[@]}" <<'SQL'
\pset quiet on
\pset tuples_only on
\pset format unaligned

\echo ### Resultado por cenário
\echo
SELECT line FROM (
    SELECT 0 AS k, 0 AS o, '| Cenário | Passo | Resultado |' AS line
    UNION ALL SELECT 0, 1, '|---|---|---|'
    UNION ALL SELECT 1, ordem, format('| %s | %s | %s |', cenario, passo, resultado)
              FROM tx_teste.resultados
) t ORDER BY k, o;
\echo
\echo ### Duração por cenário
\echo
SELECT line FROM (
    SELECT 0 AS k, 0 AS o, '| Cenário | Duração (ms) |' AS line
    UNION ALL SELECT 0, 1, '|---|---|'
    UNION ALL SELECT 1, i.ordem,
           format('| %s | %s |', i.cenario,
                  round((extract(epoch FROM f.instante - i.instante) * 1000)::numeric, 1))
      FROM tx_teste.marcas i
      JOIN tx_teste.marcas f
        ON f.cenario = i.cenario
       AND i.marco = 'inicio'
       AND f.marco = 'fim'
) t ORDER BY k, o;
\echo
\echo ### Conferência final
\echo
SELECT line FROM (
    SELECT 0 AS k, 0 AS o, '| Matrículas de teste restantes |' AS line
    UNION ALL SELECT 0, 1, '|---|'
    UNION ALL SELECT 1, 0, format('| %s |', COUNT(*))
              FROM tb_matricula m
              JOIN tx_teste.cfg c ON m.id_turma = c.id_turma
             WHERE m.id_aluno IN (c.aluno_a, c.aluno_b)
) t ORDER BY k, o;
SQL
)

# 4. Monta o relatório. As variáveis entram já preenchidas; as crases são
#    escapadas com \ para não serem interpretadas pelo shell.
cat > "$ARQ" <<EOF
# Evidências: Transações e Concorrência

**Frente:** Transações e Concorrência · Banco de Dados II (CCO072) · IESB 2026/2
**Script:** \`sql/06_transacoes.sql\`
**Gerado em:** $DATA
**PostgreSQL:** $VERSAO (Docker, banco \`matricula\`)

## Objetivo

Mostrar a disputa pela última vaga de uma turma em três situações: sem controle,
com bloqueio explícito (\`FOR UPDATE\`) e com isolamento \`SERIALIZABLE\` e retentativa.

$TABELAS

## Interpretação

- **Sem proteção:** as duas transações leem a mesma ocupação antes de confirmar e
  ambas inserem. Se o resultado mostra mais matrículas que vagas, a anomalia foi reproduzida.
- **FOR UPDATE:** a segunda transação espera o bloqueio da primeira e revalida a vaga
  antes de inserir. A duração do cenário inclui a pausa de 1 segundo do script
  (\`pg_sleep\`), usada só para garantir que a segunda sessão alcance o bloqueio.
- **SERIALIZABLE:** a segunda transação deve ser abortada com SQLSTATE 40001 ao
  confirmar. A retentativa refaz a transação inteira e não insere, porque a turma
  já está cheia.

## Saída completa da execução

<details>
<summary>Ver saída bruta do psql</summary>

\`\`\`text
$SAIDA
\`\`\`

</details>
EOF

echo "Relatório gerado em $ARQ"