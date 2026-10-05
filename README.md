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

5. Clique em **Save**.

**Host é `postgres`, não `localhost`.** O pgAdmin roda em outro contêiner; para ele, `localhost` é o próprio pgAdmin. Os contêineres se enxergam pelo nome do serviço no `docker-compose.yml`, que é `postgres`.

## Rodando os scripts SQL no pgAdmin

Os scripts são executados **manualmente, um por vez, no Query Tool**, na ordem da numeração:

| Ordem | Arquivo | O que faz |
|---|---|---|
| 1 | [sql/01_ddl.sql](sql/01_ddl.sql) | extensão, tipos, domínios e as 16 tabelas com constraints |
| 2 | [sql/02_carga.sql](sql/02_carga.sql) | carga de dados |
| 3 | [sql/03_consultas.sql](sql/03_consultas.sql) | as 10 consultas do Marco 1 |

`04` a `08` compõem o Marco 2 e seguem a mesma ordem.

### Passo a passo

1. Na árvore, expanda **Servers → matricula (bd2) → Databases** e clique no banco **`matricula`** (não no `postgres`).
2. Abra o Query Tool: menu **Tools → Query Tool** (ou botão direito em `matricula` → **Query Tool**).
3. Abra o arquivo do script no editor (VS Code, por exemplo), copie todo o conteúdo (**Ctrl+A**, **Ctrl+C**) e cole no Query Tool (**Ctrl+V**).
4. Execute o script inteiro com **F5** (ou o botão ▶ **Execute script**).
5. Confira a aba **Messages** antes de passar para o próximo script.
6. Para o script seguinte, limpe o editor (**Ctrl+A**, **Delete**) e repita a partir do passo 3.

### O que conferir em cada script

| Script | Resultado esperado na aba **Messages** |
|---|---|
| `01_ddl.sql` | `Query returned successfully`, sem erro |
| `02_carga.sql` | `NOTICE: carga ok: 120 alunos, 83 turmas, 3320 matrículas` |
| `03_consultas.sql` | ver abaixo |

Depois do `01_ddl.sql`, clique com o botão direito em **Schemas → public → Tables → Refresh**: as 16 tabelas `tb_*` aparecem.

**Consultas:** o Query Tool mostra em **Data Output** só o resultado do último comando executado. Para ver cada consulta, cole o arquivo inteiro, **selecione só a consulta desejada** (do comentário `Q1 — ...` até o `;`) e aperte **F5**: apenas o trecho selecionado é executado.

### Se der erro

- **`type ... already exists` / `relation ... already exists`:** o script já foi rodado nesse banco. Recomece do zero (seção abaixo) e rode de novo, na ordem.
- **`relation "tb_..." does not exist`:** algum script anterior não foi rodado, ou foi rodado no banco `postgres` em vez de `matricula`.
- **Tabelas não aparecem na árvore:** o pgAdmin não recarrega sozinho; botão direito em **Tables → Refresh**.

## Recomeçando do zero

Apaga o banco e sobe vazio de novo (no terminal, na pasta do projeto):

```bash
docker compose down -v
docker compose up -d
```

Depois, rode os scripts no pgAdmin outra vez, a partir do `01_ddl.sql`. O cadastro do servidor no pgAdmin também é apagado e precisa ser refeito.

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
