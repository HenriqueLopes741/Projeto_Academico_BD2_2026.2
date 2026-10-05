# Projeto Acadêmico BD2 2026.2 — Sistema de Matrícula Acadêmica

Banco de Dados II (CCO072) — Centro Universitário IESB — 2026/2 — Prof. Rodrigo Gonçalves

Autores: ver [AUTORES.md](AUTORES.md).

## Antes do Código
Após feedback do professor em 24 de agosto sobre a importância de seguir as etapas iniciais de desenvolvimento, a equipe priorizou a modelagem do banco de dados. Utilizando a ferramenta Draw.io, revisamos a estrutura e corrigimos erros presentes no modelo lógico inicial da disciplina. Os diagramas dos modelos conceitual e lógico resultantes estão disponíveis abaixo.

### Modelo lógico

Modelo lógico v4 do sistema (16 tabelas). O DDL em `sql/01_ddl.sql` segue exatamente os nomes deste diagrama.

Diagrama: [modelo_logico_v4.drawio.pdf](modelo_logico_v4.drawio.pdf). A página 2 traz os tipos enumerados, domínios, `timerange`, colunas geradas e as decisões deliberadas; as definições estão em [sql/01_ddl.sql](sql/01_ddl.sql) (Parte 1).

A v4 não muda a estrutura da v3; organiza o modelo: tabelas com prefixo `TB_` (no banco, `tb_`), atributos na ordem PK → FK → texto → numéricos → demais, e o DDL num único script com as constraints dentro de cada `CREATE TABLE`.

A v3 corrigiu dois pontos da v2: `pre_requisito` passou a ser por currículo (`id_curriculo`), porque a mesma disciplina tem exigências diferentes em CCO e ECO, e `turma_horario` passou a guardar `id_periodo_letivo`, para o EXCLUDE de sala ocupada separar semestres.

Convenção de nomes: tabela = `TB_<nome>` (no banco, `tb_<nome>`), atributo = `<atributo>_<tabela>` (ex.: `nome_campus`), PK = `id_<tabela>`, FK = mesmo nome da PK que referencia. Quando há duas FK para a mesma tabela, a segunda leva o papel no nome (`id_disciplina_requisito`).

## Pré-requisito

Docker (Desktop ou Engine). Nenhuma outra dependência — PostgreSQL 17 e pgAdmin rodam em contêiner.

## Subindo o ambiente do zero

```bash
docker compose up -d
```

Isso levanta:

| Serviço | Endereço | Credenciais |
|---|---|---|
| PostgreSQL 17 | `localhost:5432` | usuário `bd2` · senha `bd2` · base `matricula` |
| pgAdmin | http://localhost:8080 | login `admin@iesb.br` · senha `admin` |

A base `matricula` sobe **vazia**. O esquema é criado pelos scripts em `sql/`.

## Rodando os scripts SQL

Os arquivos em `sql/` são numerados na ordem real de execução. Rodar `01` → `05` num banco vazio levanta o Marco 1 completo (tipos, tabelas, constraints, carga e consultas):

```bash
for f in sql/0{1,2,3,4,5}_*.sql; do
  docker compose exec -T postgres psql -U bd2 -d matricula -v ON_ERROR_STOP=1 -f - < "$f"
done
```

Deu certo se aparecer `NOTICE: carga ok: 120 alunos, 83 turmas, 3320 matrículas`, seguido do resultado das 10 consultas. Para conferir as tabelas pelo terminal:

```bash
docker compose exec postgres psql -U bd2 -d matricula -c '\dt'
```

`06` a `10` compõem o Marco 2 e são rodados depois, na mesma ordem numérica.

## Conectando no pgAdmin

1. Abra http://localhost:8080 e entre com `admin@iesb.br` / `admin`.
2. Na árvore à esquerda, clique com o botão direito em **Servers → Register → Server…**
3. Aba **General**: em **Name**, dê um nome qualquer (ex.: `matricula (bd2)`).
4. Aba **Connection**:

   | Campo | Valor |
   |---|---|
   | Host name/address | `postgres` |
   | Port | `5432` |
   | Maintenance database | `matricula` |
   | Username | `bd2` |
   | Password | `bd2` (marque **Save password**) |

5. Clique em **Save**. As tabelas ficam em:

   ```
   Servers → matricula (bd2) → Databases → matricula → Schemas → public → Tables
   ```

**Host é `postgres`, não `localhost`.** O pgAdmin roda dentro do próprio contêiner, e para ele `localhost` é o contêiner do pgAdmin. Os contêineres se enxergam pelo nome do serviço no `docker-compose.yml`, que é `postgres`. Para conectar de fora do Docker (DBeaver, VS Code, `psql` local), aí sim use `localhost:5432`.

**Não aparece nenhuma tabela?**

- O banco sobe vazio: rode os scripts da seção anterior.
- O pgAdmin não recarrega sozinho: botão direito em **Tables → Refresh**.
- Confira se abriu o banco `matricula`, e não o `postgres`.

## Recomeçando do zero

```bash
docker compose down -v   # apaga os dados
docker compose up -d     # sobe limpo de novo
# rodar os scripts sql/ novamente
```

## Estrutura do repositório

```
docker-compose.yml        # ambiente Docker (PostgreSQL 17 + pgAdmin)
sql/                       # scripts SQL numerados na ordem de execução
scripts/                   # ferramental de teste, verificação e automação
modelo_logico_v4.drawio.pdf # diagrama do modelo lógico v4 (2 páginas)
evidencias/explain.md      # EXPLAIN (ANALYZE, BUFFERS) antes/depois dos índices
AUTORES.md                 # integrantes e frente de cada um
```

## Frentes do grupo

Cada integrante tem uma responsabilidade técnica formal (ver Seção 3 do enunciado) e é avaliado individualmente na arguição cruzada sobre a frente de **outro** colega — ver [AUTORES.md](AUTORES.md).

## Marcos

| Marco | Conteúdo | Data |
|---|---|---|
| Marco 1 | DDL completo, carga (≥100 alunos, ≥6 turmas, ≥300 matrículas), 10 consultas | 14/09/2026 |
| Marco 2 | views, índices, transações, segurança/RLS, backup/restauração | 06/11/2026 |
