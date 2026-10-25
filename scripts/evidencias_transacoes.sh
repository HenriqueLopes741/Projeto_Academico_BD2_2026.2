#!/usr/bin/env bash
# Executa sql/06_transacoes.sql e gera evidencias/transacoes.md com os dados
# reais da execução. As tabelas em Markdown são montadas pelo próprio SQL.
#
# Uso, a partir da raiz do projeto:
#   bash scripts/evidencias_transacoes.sh

set -uo pipefail
cd "$(dirname "$0")/.."

ARQ="evidencias/transacoes.md"
PSQL=(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U bd2 -d matricula)
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
if [ $? -ne 0 ]; then
    echo "Falha ao consultar a versão do PostgreSQL. Relatório não gerado."
    exit 1
fi
DATA=$(date '+%d/%m/%Y %H:%M')

# 3. Tabelas em Markdown. Cada linha é montada no SQL com format(), então a
#    saída já sai com barras verticais, que é o que o Markdown renderiza.
TABELAS=$("${PSQL[@]}" <<'SQL'
\set QUIET on
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
\echo ### Espera da transação B no FOR UPDATE
\echo
SELECT line FROM (
    SELECT 0 AS k, 0 AS o, '| Medida | Tempo (ms) |' AS line
    UNION ALL SELECT 0, 1, '|---|---|'
    UNION ALL SELECT 1, 0,
           format('| Do envio de B até o COMMIT de A | %s |',
                  round((extract(epoch FROM a.instante - b.instante) * 1000)::numeric, 1))
      FROM tx_teste.marcas b
      JOIN tx_teste.marcas a
        ON a.cenario = '2-FOR UPDATE' AND a.marco = 'a_commit'
     WHERE b.cenario = '2-FOR UPDATE' AND b.marco = 'b_envia'
) t ORDER BY k, o;
\echo
\echo ### Comparação entre os cenários
\echo
WITH dur AS (
    SELECT i.cenario,
           round((extract(epoch FROM f.instante - i.instante) * 1000)::numeric, 1) AS ms
      FROM tx_teste.marcas i
      JOIN tx_teste.marcas f
        ON f.cenario = i.cenario
       AND i.marco = 'inicio'
       AND f.marco = 'fim'
)
SELECT line FROM (
    SELECT 0 AS k, 0 AS o, '| Cenário | Resultado | Contenção | Custo (ms) | Retentativa |' AS line
    UNION ALL SELECT 0, 1, '|---|---|---|---|---|'
    UNION ALL SELECT 1, 1,
           format('| 1. Sem proteção | %s | nenhuma | %s | não |',
                  (SELECT resultado FROM tx_teste.resultados
                    WHERE cenario = '1-sem protecao' AND passo = 'overbooking'),
                  (SELECT ms FROM dur WHERE cenario = '1-sem protecao'))
    UNION ALL SELECT 1, 2,
           format('| 2. FOR UPDATE | %s | B espera o bloqueio de A | %s | não |',
                  (SELECT resultado FROM tx_teste.resultados
                    WHERE cenario = '2-FOR UPDATE' AND passo = 'B espera A e nao insere'),
                  (SELECT ms FROM dur WHERE cenario = '2-FOR UPDATE'))
    UNION ALL SELECT 1, 3,
           format('| 3. SERIALIZABLE | %s | aborto de B no COMMIT (40001) | %s | sim: %s retentativa(s) (%s tentativas no total) |',
                  (SELECT resultado FROM tx_teste.resultados
                    WHERE cenario = '3-SERIALIZABLE' AND passo = 'resultado final'),
                  (SELECT ms FROM dur WHERE cenario = '3-SERIALIZABLE'),
                  (SELECT COUNT(*) - 1 FROM tx_teste.resultados
                    WHERE cenario = '3-SERIALIZABLE' AND passo LIKE 'B tentativa%'),
                  (SELECT COUNT(*) FROM tx_teste.resultados
                    WHERE cenario = '3-SERIALIZABLE' AND passo LIKE 'B tentativa%'))
) t ORDER BY k, o;
\echo
\echo *O custo do cenário 2 inclui a espera de B, medida na tabela de espera acima.*
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
if [ $? -ne 0 ]; then
    echo "Falha ao montar as tabelas do relatório. Relatório não gerado."
    exit 1
fi

# 4. Relatório. As variáveis entram já preenchidas; as crases são escapadas
#    com \ para não serem interpretadas pelo shell.
cat > "$ARQ" <<EOF
# Evidências: Transações e Concorrência

**Frente:** Transações e Concorrência · Banco de Dados II (CCO072) · IESB 2026/2
**Script:** \`sql/06_transacoes.sql\`
**Gerado em:** $DATA
**PostgreSQL:** $VERSAO (Docker, banco \`matricula\`)

## Objetivo

Mostrar a disputa pela última vaga de uma turma em três situações: sem bloqueio,
com bloqueio explícito (\`FOR UPDATE\`) e com isolamento \`SERIALIZABLE\` e retentativa.
Os dados abaixo são os da execução que gerou este arquivo.

$TABELAS

## A anomalia: write skew

A regra do sistema é: o número de matrículas que ocupam vaga não pode passar de
\`vagas_turma\`. No cenário 1, cada transação lê o mesmo conjunto de matrículas da
turma (40 ocupadas), conclui que há vaga e grava uma linha nova. As duas linhas são
diferentes (aluno A e aluno B), então nenhuma transação escreve sobre uma linha que a
outra alterou. Não há conflito direto de escrita, e mesmo assim a regra é violada.

Esse padrão tem nome: **write skew**. Duas transações leem um conjunto em comum,
escrevem em registros disjuntos com base nessa leitura, e o resultado final viola uma
restrição que cada uma, isoladamente, respeitava. A inserção da outra transação também
muda o resultado da consulta, por isso o caso se aproxima do fenômeno de *phantom*.

## Por que o REPEATABLE READ não resolve este caso

No REPEATABLE READ, toda a transação usa o snapshot tirado na primeira consulta. A
transação B não enxerga a inserção de A, porque ela ainda não foi confirmada, e continua
contando 40 ocupadas. O PostgreSQL só aborta por conflito de escrita quando as duas
transações alteram a mesma linha. Aqui as linhas são diferentes, então nenhuma aborta,
e o overbooking acontece do mesmo jeito. Por isso esse caso exige SERIALIZABLE, que
rastreia dependências de leitura e escrita entre as transações.

## Por que o FOR UPDATE depende de READ COMMITTED

No cenário 2, A bloqueia a linha da turma. B tenta o mesmo bloqueio e espera. Quando A
confirma, B obtém o bloqueio, mas ainda precisa decidir se há vaga, e essa decisão
depende da leitura feita depois da espera.

Em READ COMMITTED, cada comando recebe um snapshot novo. O INSERT de B roda depois do
COMMIT de A, então enxerga a matrícula de A, conta 41 e não insere. Essa é a condição
que faz o bloqueio funcionar.

Em REPEATABLE READ, o snapshot da transação de B foi tirado antes da espera. Mesmo
depois de obter o bloqueio, o INSERT de B continuaria contando 40 ocupadas e inseriria,
gerando overbooking. O bloqueio só serializa o acesso; quem garante que a leitura
reflete o estado atual é o snapshot por comando do READ COMMITTED. O problema é
silencioso: o SELECT ... FOR UPDATE não dá erro nenhum nesse caso.

## Medição da espera

A espera de B é medida com \`clock_timestamp()\`: do instante em que B é enviada até o
instante em que A confirma e libera o bloqueio. Essa espera é a contenção real do
cenário 2. A duração total do cenário é pequena, porque o script não usa mais
\`pg_sleep\` fixo: um laço verifica que B está bloqueada antes de A confirmar.

## Permissões

\`SELECT ... FOR UPDATE\` exige o privilégio \`UPDATE\` na tabela \`tb_turma\`. O script
roda como \`bd2\`, dono do banco, então funciona aqui. O role usado pela aplicação de
matrículas precisa desse privilégio, concedido com \`GRANT UPDATE ON tb_turma\`.

## Cenário 3: SERIALIZABLE

O PostgreSQL acompanha as leituras e escritas de transações SERIALIZABLE. Quando detecta
uma estrutura perigosa, que é exatamente o padrão do write skew, aborta uma das
transações com SQLSTATE 40001. A aplicação deve repetir a transação inteira. Na nova
tentativa, a turma já está cheia e nenhuma linha é inserida.

## Saída completa da execução

<details>
<summary>Ver saída bruta do psql</summary>

\`\`\`text
$SAIDA
\`\`\`

</details>
EOF

echo "Relatório gerado em $ARQ"