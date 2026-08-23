# Como executar o projeto

## Pré-requisitos

Antes de começar, confirme se o Docker e o Docker Compose estão instalados no seu computador.

- Docker: https://www.docker.com/products/docker-desktop/
- Docker Compose: normalmente já vem junto com o Docker Desktop

## Ambiente configurado pelo projeto

O projeto usa o seguinte ambiente definido no `docker-compose.yml`:

- Serviço PostgreSQL: `postgres`
- Container PostgreSQL: `bd2_aluno_postgres`
- Imagem: `postgres:17`
- Usuário: `bd2`
- Senha: `bd2`
- Banco: `matricula`
- Porta do PostgreSQL no host: `localhost:5432`
- Porta do pgAdmin no host: `http://localhost:8080`
- Volume persistente: `bd2_aluno_dados`

## 1. Iniciar o banco normalmente

Se o banco ainda não foi criado, ou se você deseja apenas iniciar o ambiente existente, execute:

```bash
docker compose up -d
```

Esse comando inicia os containers do PostgreSQL e do pgAdmin.

> Importante: `docker compose down` não remove os dados, porque o projeto usa um volume persistente chamado `bd2_aluno_dados`.
>
> Para apagar o banco e reiniciar do zero, use:
>
> ```bash
> docker compose down -v
> ```
>
> O comando `down -v` remove o volume e limpa os dados do banco. Use isso somente quando realmente for necessário reiniciar completamente o ambiente.

## 2. Executar os scripts SQL

Os arquivos SQL ficam na pasta `./sql` do projeto e devem ser enviados ao PostgreSQL pelo terminal do computador, usando entrada padrão (`<`) em vez de tentar buscar o arquivo dentro do container.

### Forma correta de execução

Use este padrão:

```bash
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/01_tipos_dominios.sql
```

Esse comando envia o conteúdo do arquivo local para o PostgreSQL dentro do container. Isso funciona corretamente porque o arquivo existe no computador do usuário e não dentro do contêiner.

### Alternativa usando o nome do container

Se preferir usar o nome do container em vez do nome do serviço do Compose, a forma correta é:

```bash
docker exec -i bd2_aluno_postgres psql -U bd2 -d matricula < ./sql/01_tipos_dominios.sql
```

### Execução em sequência

Os scripts devem ser executados na ordem correta para construir o banco do zero:

```bash
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/01_tipos_dominios.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/02_tabelas.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/03_constraints.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/04_carga.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/05_consultas.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/06_views.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/07_indices.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/08_transacoes.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/09_seguranca_rls.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/10_backup_restore.sql
```

### Ordem de execução

1. `01_tipos_dominios.sql` — cria extensões, tipos e domínios;
2. `02_tabelas.sql` — cria as tabelas;
3. `03_constraints.sql` — aplica as constraints e regras;
4. `04_carga.sql` — insere os dados iniciais;
5. `05_consultas.sql` — scripts de consultas;
6. `06_views.sql` — cria as views;
7. `07_indices.sql` — cria índices;
8. `08_transacoes.sql` — scripts de transação;
9. `09_seguranca_rls.sql` — segurança e RLS;
10. `10_backup_restore.sql` — backup e restauração.

> Atenção: scripts de criação, como `01_tipos_dominios.sql`, não devem ser executados novamente em um banco que já possui os objetos criados. Isso pode gerar erros como `type already exists` ou `relation already exists`.

## 3. Como começar do zero

Se quiser reiniciar o banco completamente:

```bash
docker compose down -v
docker compose up -d
```

Depois, execute os scripts em ordem:

```bash
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/01_tipos_dominios.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/02_tabelas.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/03_constraints.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/04_carga.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/05_consultas.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/06_views.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/07_indices.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/08_transacoes.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/09_seguranca_rls.sql
docker compose exec -T postgres psql -U bd2 -d matricula < ./sql/10_backup_restore.sql
```

## 4. Como iniciar um banco já existente

Se o ambiente já foi configurado e você quer apenas continuar trabalhando:

```bash
docker compose up -d
```

Nesse caso, não execute novamente os scripts de criação se eles já tiverem sido executados antes.

## 5. Encerrar o ambiente

Quando terminar de trabalhar, rode:

```bash
docker compose down
```

Esse comando encerra os containers. Como existe um volume persistente, os dados do banco continuam salvos.

## 6. Acesso ao pgAdmin

Acesse o pgAdmin no navegador:

- URL: `http://localhost:8080`
- Email: `admin@iesb.br`
- Senha: `admin`

### Conexão do PostgreSQL no pgAdmin

Ao criar uma conexão no pgAdmin, use:

- Host: `postgres`
- Porta: `5432`
- Banco: `matricula`
- Usuário: `bd2`
- Senha: `bd2`

### Diferença entre localhost e postgres

- Quando você acessa o PostgreSQL pelo computador local, usa `localhost:5432`.
- Quando o pgAdmin acessa o PostgreSQL, ele está dentro da mesma rede Docker, então o host correto é `postgres` e a porta continua `5432`.

Em outras palavras:

- `localhost:5432` = acesso do host (seu computador)
- `postgres:5432` = acesso dentro da rede Docker (do pgAdmin, por exemplo)

## 7. Observações finais

- O banco principal do projeto é `matricula`.
- Certifique-se de executar os scripts na ordem correta.
- Não use `-f sql/arquivo.sql` diretamente dentro do `docker compose exec` quando o arquivo está no computador do usuário, porque o `psql` procura esse caminho dentro do container.
- A forma correta é enviar o arquivo por entrada padrão (`< ./sql/...`) ou copiar o arquivo para dentro do contêiner somente se houver necessidade específica.

---

