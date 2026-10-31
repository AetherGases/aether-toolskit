# Backup e Recuperação — PostgreSQL (dbAether1Year / dbAether2Year)

Procedimentos para o cluster do `compose.yaml` (container `aether_postgres`, usuário `sa`). Todos os comandos abaixo foram executados em um Postgres 16.10 descartável: o dump de `dbAether2Year` (701 KB) foi restaurado em um banco novo e as contagens bateram (500 `enterprise`, 507 `emission`, 10 000 `daily_active_user`, 5 views).

## 1. O que proteger

| Item | Banco | Observação |
| --- | --- | --- |
| Banco normalizado (3FN) | `dbAether2Year` | Fonte de verdade do BI, auditoria e catálogo |
| Banco legado | `dbAether1Year` | Origem da carga do RPA; o outbox `rpa_outbox` vive nele |
| Roles e grants | cluster | `aether_app`, `aether_auditor`, `aether_admin` (script `03`) não entram no `pg_dump` de um banco |

## 2. Política

| Tipo | Frequência | Retenção | Ferramenta |
| --- | --- | --- | --- |
| Lógico completo | diário, 02:00 | 7 diários + 4 semanais | `pg_dump -Fc` |
| Roles/globais | diário, junto ao dump | igual | `pg_dumpall --globals-only` |
| Contínuo (PITR) | opcional, produção | 7 dias | arquivamento de WAL (`archive_mode=on`) |

Os dumps ficam fora do volume `postgres_data`, em armazenamento separado, e a cópia mais recente é verificada com `pg_restore -l` depois de gerada.

## 3. Backup

```bash
STAMP=$(date +%Y%m%d_%H%M)
docker exec -e PGPASSWORD=$POSTGRES_PASSWORD aether_postgres \
  pg_dump -U sa -Fc -d dbAether2Year -f /tmp/dbAether2Year_$STAMP.dump
docker exec -e PGPASSWORD=$POSTGRES_PASSWORD aether_postgres \
  pg_dump -U sa -Fc -d dbAether1Year -f /tmp/dbAether1Year_$STAMP.dump
docker exec -e PGPASSWORD=$POSTGRES_PASSWORD aether_postgres \
  pg_dumpall -U sa --globals-only -f /tmp/globals_$STAMP.sql
docker cp aether_postgres:/tmp/dbAether2Year_$STAMP.dump ./backups/
```

Validação obrigatória (falha se o arquivo estiver corrompido):

```bash
docker exec aether_postgres pg_restore -l /tmp/dbAether2Year_$STAMP.dump > /dev/null && echo OK
```

## 4. Recuperação

### 4.1 Perda total do banco

```bash
psql -U sa -d postgres -f globals_$STAMP.sql          # roles primeiro
psql -U sa -d postgres -c 'CREATE DATABASE "dbAether2Year"'
pg_restore -U sa -d dbAether2Year --no-owner --exit-on-error dbAether2Year_$STAMP.dump
```

`--exit-on-error` impede restore parcial silencioso. Depois, conferir:

```sql
SELECT count(*) FROM enterprise;
SELECT * FROM fn_metadata_completeness();   -- deve retornar 0 linhas
```

### 4.2 Restaurar uma única tabela (erro humano)

```bash
pg_restore -U sa -d dbAether2Year --data-only -t emission --disable-triggers dbAether2Year_$STAMP.dump
```

Testado: `TRUNCATE emission CASCADE` seguido do comando acima voltou de 0 para 507 linhas. `--disable-triggers` evita gerar eventos de auditoria duplicados durante o restore e exige superusuário.

### 4.3 Ponto no tempo (PITR)

Requer `archive_mode=on`, `archive_command` configurado e um *base backup* (`pg_basebackup -Ft -z`). Para voltar a um instante: restaurar o base backup, definir `recovery_target_time` em `postgresql.conf` e criar `recovery.signal`. Não está habilitado no `compose.yaml` de desenvolvimento.

### 4.4 Pós-restauração do RPA

Se `dbAether1Year` foi restaurado a partir de um dump antigo, `rpa_outbox` pode conter eventos já processados ou não. O worker é idempotente (`INSERT … ON CONFLICT`), então basta reiniciá-lo: ele drena o que estiver com `processed_at IS NULL`.

## 5. Teste de recuperação

Executar a cada trimestre (e após mudança de schema): restaurar o último dump em `dbRestoreTest`, comparar contagens com a origem e descartar o banco. Registrar data e resultado.

## 6. Responsabilidades e segurança

- Quem executa: papel `aether_admin` / DBA do projeto.
- Dumps contêm hashes de senha (`password_hash`) e dados pessoais (CPF, e-mail): guardar com acesso restrito e criptografia em repouso.
- `audit_row_event` e `audit_row_update` entram no dump; o purge de auditoria (`sp_purge_audit_events`) não substitui backup.
- No Neon, usar a retenção/branching nativos do provedor além dos dumps acima.
