# Evidências: Transações e Concorrência

**Frente:** Transações e Concorrência · Banco de Dados II (CCO072) · IESB 2026/2
**Script:** `sql/06_transacoes.sql`
**Gerado em:** 24/10/2026 12:36
**PostgreSQL:** 17.11 (Docker, banco `matricula`)

## Objetivo

Mostrar a disputa pela última vaga de uma turma em três situações: sem bloqueio,
com bloqueio explícito (`FOR UPDATE`) e com isolamento `SERIALIZABLE` e retentativa.
Os dados abaixo são os da execução que gerou este arquivo.

Output format is unaligned.
### Resultado por cenário

| Cenário | Passo | Resultado |
|---|---|---|
| 1-sem protecao | overbooking | matriculas 42 para vagas 41 |
| 2-FOR UPDATE | B espera A e nao insere | matriculas 41 para vagas 41 |
| 3-SERIALIZABLE | B tentativa 1 | abortada com 40001 |
| 3-SERIALIZABLE | B tentativa 2 | INSERT 0 0 e COMMIT ok |
| 3-SERIALIZABLE | resultado final | matriculas 41 para vagas 41 |

### Duração por cenário

| Cenário | Duração (ms) |
|---|---|
| 1-sem protecao | 5.0 |
| 2-FOR UPDATE | 4.1 |
| 3-SERIALIZABLE | 4.5 |

### Espera da transação B no FOR UPDATE

| Medida | Tempo (ms) |
|---|---|
| Do envio de B até o COMMIT de A | 1.2 |

### Conferência final

| Matrículas de teste restantes |
|---|
| 0 |

## A anomalia: write skew

A regra do sistema é: o número de matrículas que ocupam vaga não pode passar de
`vagas_turma`. No cenário 1, cada transação lê o mesmo conjunto de matrículas da
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

A espera de B é medida com `clock_timestamp()`: do instante em que B é enviada até o
instante em que A confirma e libera o bloqueio. Essa espera é a contenção real do
cenário 2. A duração total do cenário é pequena, porque o script não usa mais
`pg_sleep` fixo: um laço verifica que B está bloqueada antes de A confirmar.

## Permissões

`SELECT ... FOR UPDATE` exige o privilégio `UPDATE` na tabela `tb_turma`. O script
roda como `bd2`, dono do banco, então funciona aqui. O role usado pela aplicação de
matrículas precisa desse privilégio, concedido com `GRANT UPDATE ON tb_turma`.

## Cenário 3: SERIALIZABLE

O PostgreSQL acompanha as leituras e escritas de transações SERIALIZABLE. Quando detecta
uma estrutura perigosa, que é exatamente o padrão do write skew, aborta uma das
transações com SQLSTATE 40001. A aplicação deve repetir a transação inteira. Na nova
tentativa, a turma já está cheia e nenhuma linha é inserida.

## Saída completa da execução

<details>
<summary>Ver saída bruta do psql</summary>

```text
NOTICE:  extension "dblink" already exists, skipping
CREATE EXTENSION
 case 
------
 
(1 row)

 dblink_connect 
----------------
 OK
(1 row)

SET
 dblink_exec 
-------------
 SET
(1 row)

NOTICE:  drop cascades to 3 other objects
DETAIL:  drop cascades to table tx_teste.cfg
drop cascades to table tx_teste.resultados
drop cascades to table tx_teste.marcas
DROP SCHEMA
CREATE SCHEMA
SELECT 1
CREATE TABLE
CREATE TABLE
DELETE 0
       passo       | vagas_turma | ocupadas | vagas_livres 
-------------------+-------------+----------+--------------
 0. estado inicial |          41 |       40 |            1
(1 row)

INSERT 0 1
WARNING:  there is no transaction in progress
ROLLBACK
BEGIN
            passo            | ocupadas 
-----------------------------+----------
 A: ocupadas antes do INSERT |       40
(1 row)

INSERT 0 1
 dblink_exec 
-------------
 BEGIN
(1 row)

 ocupadas 
----------
       40
(1 row)

 b_insert_status 
-----------------
 INSERT 0 1
(1 row)

COMMIT
 b_commit_status 
-----------------
 COMMIT
(1 row)

INSERT 0 1
              passo              | vagas_turma | matriculas_ocupando_vaga 
---------------------------------+-------------+--------------------------
 1. anomalia: matriculas x vagas |          41 |                       42
(1 row)

INSERT 0 1
DELETE 2
INSERT 0 1
WARNING:  there is no transaction in progress
ROLLBACK
BEGIN
 vagas_turma 
-------------
          41
(1 row)

INSERT 0 1
 dblink_exec 
-------------
 BEGIN
(1 row)

INSERT 0 1
 dblink_send_query 
-------------------
                 1
(1 row)

DO
 pid | wait_event_type |  wait_event   
-----+-----------------+---------------
 461 | Lock            | transactionid
(1 row)

INSERT 0 1
COMMIT
 vagas 
-------
    41
(1 row)

 drenagem_b 
------------
          0
(1 row)

 b_insert_status 
-----------------
 INSERT 0 0
(1 row)

 dblink_exec 
-------------
 COMMIT
(1 row)

INSERT 0 1
               passo               | vagas_turma | matriculas_ocupando_vaga 
-----------------------------------+-------------+--------------------------
 2. FOR UPDATE: matriculas x vagas |          41 |                       41
(1 row)

INSERT 0 1
DELETE 1
INSERT 0 1
WARNING:  there is no transaction in progress
ROLLBACK
BEGIN
 ocupadas_a 
------------
         40
(1 row)

INSERT 0 1
 dblink_exec 
-------------
 BEGIN
(1 row)

 ocupadas 
----------
       40
(1 row)

 b_insert_tentativa_1 
----------------------
 INSERT 0 1
(1 row)

COMMIT
NOTICE:  B: 2 tentativa(s), confirmada=t
DO
INSERT 0 1
                passo                | vagas_turma | matriculas_ocupando_vaga 
-------------------------------------+-------------+--------------------------
 3. SERIALIZABLE: matriculas x vagas |          41 |                       41
(1 row)

INSERT 0 1
DELETE 1
    cenario     |          passo          |          resultado          
----------------+-------------------------+-----------------------------
 1-sem protecao | overbooking             | matriculas 42 para vagas 41
 2-FOR UPDATE   | B espera A e nao insere | matriculas 41 para vagas 41
 3-SERIALIZABLE | B tentativa 1           | abortada com 40001
 3-SERIALIZABLE | B tentativa 2           | INSERT 0 0 e COMMIT ok
 3-SERIALIZABLE | resultado final         | matriculas 41 para vagas 41
(5 rows)

    cenario     | duracao_ms 
----------------+------------
 1-sem protecao |        5.0
 2-FOR UPDATE   |        4.1
 3-SERIALIZABLE |        4.5
(3 rows)

 espera_b_ms 
-------------
         1.2
(1 row)

 matriculas_de_teste_restantes 
-------------------------------
                             0
(1 row)

 dblink_disconnect 
-------------------
 OK
(1 row)
```

</details>
