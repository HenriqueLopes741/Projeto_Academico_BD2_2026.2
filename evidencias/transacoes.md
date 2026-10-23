# Evidências: Transações e Concorrência

**Frente:** Transações e Concorrência · Banco de Dados II (CCO072) · IESB 2026/2
**Script:** `sql/06_transacoes.sql`
**Gerado em:** 23/10/2026 14:53
**PostgreSQL:** 17.11 (Docker, banco `matricula`)

## Objetivo

Mostrar a disputa pela última vaga de uma turma em três situações: sem controle,
com bloqueio explícito (`FOR UPDATE`) e com isolamento `SERIALIZABLE` e retentativa.

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
| 1-sem protecao | 13.7 |
| 2-FOR UPDATE | 1034.3 |
| 3-SERIALIZABLE | 21.0 |

### Conferência final

| Matrículas de teste restantes |
|---|
| 0 |

## Interpretação

- **Sem proteção:** as duas transações leem a mesma ocupação antes de confirmar e
  ambas inserem. Se o resultado mostra mais matrículas que vagas, a anomalia foi reproduzida.
- **FOR UPDATE:** a segunda transação espera o bloqueio da primeira e revalida a vaga
  antes de inserir. A duração do cenário inclui a pausa de 1 segundo do script
  (`pg_sleep`), usada só para garantir que a segunda sessão alcance o bloqueio.
- **SERIALIZABLE:** a segunda transação deve ser abortada com SQLSTATE 40001 ao
  confirmar. A retentativa refaz a transação inteira e não insere, porque a turma
  já está cheia.

## Saída completa da execução

<details>
<summary>Ver saída bruta do psql</summary>

```text
CREATE EXTENSION
NOTICE:  extension "dblink" already exists, skipping
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
ROLLBACK
WARNING:  there is no transaction in progress
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

 dblink_send_query 
-------------------
                 1
(1 row)

 pg_sleep 
----------
 
(1 row)

 b_bloqueada 
-------------
           1
(1 row)

 pid  | wait_event_type |  wait_event   
------+-----------------+---------------
 3815 | Lock            | transactionid
(1 row)

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
ROLLBACK
BEGIN
WARNING:  there is no transaction in progress
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
 1-sem protecao |       13.7
 2-FOR UPDATE   |     1034.3
 3-SERIALIZABLE |       21.0
(3 rows)

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
