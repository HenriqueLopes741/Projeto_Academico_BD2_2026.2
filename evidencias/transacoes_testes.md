# Evidências: Transações e Concorrência

**Frente:** Transações e Concorrência · Banco de Dados II (CCO072) · IESB 2026/2
**Script:** `sql/06_transacoes.sql`
**Execução:** 23/10/2026, PostgreSQL 17 (Docker), banco `matricula`
**Turma de teste:** `CCODM2B-BD2` (Banco de Dados II, 2026/2), 41 vagas, 40 matrículas ativas no início

---

## Resumo

Uma única vaga livre foi disputada por duas transações concorrentes, em três variantes de controle.

| Cenário | Mecanismo | Resultado | Contenção | Custo | Retentativa |
|---|---|---|---|---|---|
| 1. Sem proteção | nenhum | **42 matrículas para 41 vagas** (overbooking) | nenhuma | 11 ms | não |
| 2. Bloqueio explícito | `SELECT ... FOR UPDATE` | **41 para 41**, correto | B espera A liberar o bloqueio | ~11 ms de trabalho, mais a espera | não |
| 3. Isolamento SERIALIZABLE | `BEGIN ISOLATION LEVEL SERIALIZABLE` | **41 para 41**, correto | B é abortada no commit (SQLSTATE 40001) | 26 ms | **sim**: 1 aborto e 1 retentativa |

**Conclusão:** sem controle, a regra de vagas é violada. As duas correções impedem o overbooking. A correção por bloqueio faz a transação concorrente esperar. A correção por isolamento deixa as duas executarem e aborta uma delas, que precisa ser repetida pela aplicação.

---

## Cenário 1: sem proteção (anomalia)

As duas transações fazem o mesmo caminho: consultam a ocupação e depois inserem.

1. A consulta a ocupação e insere `aluno_a`. Não confirma.
2. B consulta a ocupação. Como A ainda não confirmou, B vê **40 ocupadas** e 1 vaga livre.
3. B insere `aluno_b`.
4. A confirma (`COMMIT`). B confirma (`COMMIT`).

Ambas as verificações foram feitas sobre o mesmo estado, então as duas inserções passaram. A conferência final mostra **42 matrículas ocupando 41 vagas**.

Esse é o problema que a disciplina pede para demonstrar: a verificação de vaga e a inserção não são atômicas em conjunto.

---

## Cenário 2: bloqueio explícito (`SELECT ... FOR UPDATE`)

1. A bloqueia a linha da turma com `FOR UPDATE`, insere `aluno_a` com verificação de vaga e ainda não confirma.
2. B tenta o mesmo `FOR UPDATE` sobre a mesma turma e **fica bloqueada**. A evidência:
   - `dblink_is_busy = 1` (B ainda não terminou);
   - `pg_stat_activity` mostra B com `wait_event_type = Lock` e `wait_event = transactionid`.
3. A confirma e libera o bloqueio.
4. B obtém o bloqueio, recalcula a ocupação (já inclui `aluno_a`) e tenta inserir. Resultado: **`INSERT 0 0`**, ou seja, nenhuma linha inserida, porque a turma já está cheia.

A conferência final mostra **41 matrículas para 41 vagas**.

**Sobre o tempo:** o cenário levou cerca de 1 segundo, mas quase tudo é o `pg_sleep(1)` do script, que existe só para dar tempo de B alcançar o bloqueio. O trabalho em si custou pouco (cerca de 11 ms). O custo real desse mecanismo é a espera: B fica parada enquanto A não confirma.

---

## Cenário 3: isolamento SERIALIZABLE, com retentativa

1. A abre uma transação `SERIALIZABLE`, verifica a ocupação e insere `aluno_a` (sem confirmar).
2. B abre uma transação `SERIALIZABLE`, verifica a ocupação (vê 40) e insere `aluno_b`. Nenhuma das duas espera a outra.
3. A confirma primeiro. Sucesso.
4. B tenta confirmar e recebe **SQLSTATE 40001** (`serialization_failure`). O PostgreSQL detectou que as duas transações liam e escreviam dados uma da outra, e não há ordem serial que aceite as duas.
5. O script repete a transação inteira de B (**retentativa**). Agora a consulta vê a turma cheia (41 ocupadas), o `INSERT` não insere nada (`INSERT 0 0`), e o commit é aceito.

Resultado: **41 matrículas para 41 vagas**. O custo aqui é o trabalho descartado no aborto mais a repetição. Nenhuma das transações espera a outra, mas uma delas precisa ser refeita.

---

## Comparação

| Critério | 1. Sem proteção | 2. `FOR UPDATE` | 3. `SERIALIZABLE` |
|---|---|---|---|
| **Integridade (vagas)** | falha: 42 para 41 | correta | correta |
| **Contenção** | nenhuma, mas viola a regra | a transação concorrente espera pelo bloqueio | nenhuma espera; conflito detectado ao confirmar |
| **Custo de execução** | mínimo | baixo, mas serializa as transações sobre a turma | aborto e reexecução do trabalho da transação |
| **Necessidade de retentativa** | não | não | **sim**, a aplicação deve repetir em caso de `40001` |
| **Esforço na aplicação** | nenhum (e incorreto) | baixo | médio: laço de retentativa com tratamento de `40001` |

**Quando usar cada uma:**
- `FOR UPDATE` é indicado quando a disputa é concentrada num recurso conhecido (aqui, uma turma), porque o código fica simples e não há abortos.
- `SERIALIZABLE` é indicado quando a regra envolve leituras de vários registros e não há um recurso único para bloquear. O custo é ter de tratar `40001` na aplicação.

---

## Limitações

- **Uma execução.** Os tempos apresentados são de uma única execução. Para um valor mais confiável, a média de 3 a 5 execuções deve ser registrada.
- **Duas transações concorrentes.** Com mais clientes disputando a mesma vaga, a espera do `FOR UPDATE` cresce e a taxa de abortos do `SERIALIZABLE` também.
- **Ambiente local.** Os tempos dependem da máquina e do Docker. Servem para comparar os mecanismos entre si, não como medida absoluta.
- **Sessão B via `dblink`.** A segunda conexão é aberta pelo próprio script, para que a concorrência aconteça num único arquivo. Isso simula dois clientes, mas é uma aproximação de clientes reais.

---

## Saída completa

A saída bruta do psql, sem edição, está em `evidencias/transacoes.md` na versão anterior. Para regenerá-la:

```bash
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/06_transacoes.sql 2>&1
```