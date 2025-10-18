# Guia Prático — Spring Boot 3.x + AWS Advanced JDBC Wrapper com `readWriteSplitting` (Aurora MySQL)

Conteúdo gerado automaticamente. Versão completa abaixo.

> Documento de referência completo, com explicações **de cada configuração**, **valores _default_**, como **obter números reais** (dimensionamento), exemplos práticos com **AWS Secrets Manager**, boas práticas de **mercado** e checklist de implantação.

---

## Sumário
- [Objetivo e visão geral](#objetivo-e-visão-geral)
- [Arquitetura recomendada](#arquitetura-recomendada)
- [Dependências (pomxml)](#dependências-pomxml)
- [Como obter números reais (dimensionamento)](#como-obter-números-reais-dimensionamento)
- [Tabela de Configurações (com _defaults_ e como escolher)](#tabela-de-configurações-com-defaults-e-como-escolher)
  - [HikariCP](#hikaricp)
  - [AWS Advanced JDBC Wrapper](#aws-advanced-jdbc-wrapper)
  - [MySQL ConnectorJ](#mysql-connectorj)
  - [JPA/Hibernate](#jpahibernate)
- [Configuração por ambiente (exemplo: **hom**)](#configuração-por-ambiente-exemplo-hom)
- [Como o split funciona no código](#como-o-split-funciona-no-código)
- [RDS Proxy — combinação correta](#rds-proxy--combinação-correta)
- [Observabilidade, validação e troubleshooting](#observabilidade-validação-e-troubleshooting)
- [Segurança (IAM) e rede](#segurança-iam-e-rede)
- [Checklist de implantação](#checklist-de-implantação)
- [Apêndice: Segredo único JSON (opcional)](#apêndice-segredo-único-json-opcional)

---

## Objetivo e visão geral

- **O que é**: o *AWS Advanced JDBC Wrapper* “envolve” o driver MySQL e adiciona plugins (ex.: `readWriteSplitting`, `failover`).  
- **O que resolve**: envia **transações `readOnly`** para o **endpoint de leitura (reader)** e mantém demais operações no **endpoint de escrita (writer)** — sem precisar criar um *roteador* (`AbstractRoutingDataSource`).  
- **Como decide**: o Spring marca conexões como somente leitura quando você usa `@Transactional(readOnly = true)`. O wrapper detecta isso e direciona a conexão.

---

## Arquitetura recomendada

```
Sua App (Spring Boot 3.x)
  └── HikariCP
       └── Driver: software.amazon.jdbc.Driver (aws-wrapper)
            ├── Plugin: readWriteSplitting  --> SELECTs de transações readOnly -> Aurora Reader Endpoint
            └── Plugin: failover            --> reconexão em caso de falha
```

- **Writer endpoint**: recebe **escritas** e leituras que exijam consistência imediata (*read-your-writes*).  
- **Reader endpoint**: balanceia **leituras** entre réplicas do Aurora (eventualmente consistentes).

---

## Dependências (pom.xml)

```xml
<!-- Spring Data JPA + Hikari -->
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-data-jpa</artifactId>
</dependency>

<!-- MySQL (Aurora compatível) -->
<dependency>
  <groupId>com.mysql</groupId>
  <artifactId>mysql-connector-j</artifactId>
</dependency>

<!-- AWS Advanced JDBC Wrapper -->
<dependency>
  <groupId>software.amazon.jdbc</groupId>
  <artifactId>aws-advanced-jdbc-wrapper</artifactId>
  <version>2.6.5</version> <!-- use a mais recente estável do Maven Central -->
</dependency>

<!-- (Opcional, porém recomendado) Spring Cloud AWS Secrets Manager -->
<dependency>
  <groupId>io.awspring.cloud</groupId>
  <artifactId>spring-cloud-aws-starter-secrets-manager</artifactId>
  <version>3.4.0</version>
</dependency>
```

**Por que essas dependências?**  
- `mysql-connector-j`: driver base do MySQL (Aurora é compatível).  
- `aws-advanced-jdbc-wrapper`: fornece o driver `software.amazon.jdbc.Driver` e os plugins.  
- `spring-cloud-aws-starter-secrets-manager`: importa segredos como *PropertySource*, permitindo `${nome-do-segredo}` no `application.yml`.

---

## Como obter números reais (dimensionamento)

### 1) Estime a concorrência com a **Lei de Little**
- **Fórmula**: `concorrência ≈ throughput * latência`  
  - *Throughput* = requisições/s (ou consultas/s) da app.
  - *Latência DB* = p95/p99 do tempo gasto no banco (não o tempo total da requisição).
- **Exemplo**: 100 consultas/s com p95 de 30 ms (0,03 s) → `100 * 0,03 ≈ 3` conexões.  
  Coloque **folga** (picos): 2–3× → **6 a 9** conexões.

> Faça isso **por pool** (writer vs reader). Em geral, **reader** precisa de mais que o writer.

### 2) Levante limites e uso do Aurora
- SQL: `SHOW VARIABLES LIKE 'max_connections';`, `SHOW STATUS LIKE 'Threads_connected';`, `SHOW STATUS LIKE 'Threads_running';`  
- CloudWatch/Aurora: `DatabaseConnections`, `CPUUtilization`, `ReadLatency`, `WriteLatency`.

### 3) Métricas da App (Actuator/Micrometer)
- Hikari: `hikaricp.connections.active`, `pending`, `acquire`, `timeout`.  
- Sinais de falta de conexão: `acquire` alto, timeouts ao pegar conexão.

### 4) Teste de carga controlado
- Aumente RPS em degraus; observe p95/p99 de DB, `acquire` do Hikari, CPU do Aurora; ajuste `maximumPoolSize` **sem** estourar `DatabaseConnections`/CPU.

---

## Tabela de Configurações (com _defaults_ e como escolher)

### HikariCP

| Configuração | O que faz | Como escolher | **Default** |
|---|---|---|---|
| `maximum-pool-size` | Máximo de conexões no pool | Lei de Little × folga 2–3×, por pool | **10** |
| `minimum-idle` | Conexões ociosas mínimas | 10–30% do máximo (20% é bom começo) | **= máximo** (se não definir) |
| `connection-timeout` | Timeout para obter conexão | 20–30s comum; evite >60s | **30000 ms** |
| `validation-timeout` | Timeout de validação | 3–5s | **5000 ms** |
| `idle-timeout` | Fecha conexões ociosas | 5–15 min | **600000 ms** |
| `max-lifetime` | Vida máxima da conexão | 20–45 min (30 min funciona bem) | **1800000 ms** |
| `keepalive-time` | Sonda keep-alive | 0 (ligue só se NAT/Firewall derruba conexões) | **0** |
| `leak-detection-threshold` | Log de conexões “presas” | Use **só** em diagnóstico (5–10 s) | **0** |

### AWS Advanced JDBC Wrapper

| Configuração | O que faz | Como escolher | **Default** |
|---|---|---|---|
| `driver-class-name=software.amazon.jdbc.Driver` | Usa o driver do wrapper | Obrigatório | — |
| `url=jdbc:aws-wrapper:mysql://<writer>:3306/<db>` | Conecta via wrapper no writer | Use o endpoint writer (ou proxy writer) | — |
| `wrapperPlugins` | Habilita plugins | `readWriteSplitting,failover` | **(vazio)** |
| `readWriteSplitting.readerEndpoint` | Para onde mandar leituras | Reader endpoint (ou proxy read-only) | **(unset)** |
| `clusterId` (opcional) | Descoberta de topologia | Use se preferir descoberta por cluster/ARN | **(unset)** |

**Como valida o split:** `@Transactional(readOnly = true)` → Spring liga `setReadOnly(true)` → wrapper usa **reader**. Sem `readOnly` → **writer**.

### MySQL Connector/J

| Configuração | O que faz | Como escolher | **Default (varia por versão)** |
|---|---|---|---|
| `cachePrepStmts` | Cache de PS | **true** | *explicitar* `true` |
| `prepStmtCacheSize` | Tamanho do cache | **250** (100–500) | *explicitar* `250` |
| `prepStmtCacheSqlLimit` | Tamanho máx. do SQL em cache | **2048** (ou 4096 se SQLs longos) | *explicitar* `2048` |
| `useServerPrepStmts` | PS do lado do servidor | **true** | *explicitar* `true` |
| `useUnicode` / `characterEncoding` | Codificação | **true** + `utf8` (ou `utf8mb4`) | *explicitar* |

### JPA/Hibernate

| Configuração | O que faz | Como escolher | **Default** |
|---|---|---|---|
| `spring.jpa.hibernate.ddl-auto` | Gestão de DDL | `none` em hom/prd; `update` só em dev | **none** |
| `hibernate.dialect` | Dialeto | `MySQLDialect` (explicitar dá previsibilidade) | **auto** |
| `hibernate.jdbc.time_zone` | Fuso JDBC | **UTC** | **(unset)** |

---

## Configuração por ambiente (exemplo: **hom**)

> Substitua `<db>` pelo schema real (ex.: `gestaodividas`). Os segredos abaixo são os **seus** (nomes literais).

```yaml
spring:
  application:
    name: gestaodividas
  profiles:
    active: hom

  config:
    import:
      - aws-secretsmanager:gestaopagamentoscash-gestaodividas-awssae1aurmy-hom-RDSInstanceEndpointSecret-k4f3U
      - aws-secretsmanager:gestaopagamentoscash-gestaodividas-awssae1aurmy-hom-RDSInstanceReaderEndpointSecret-k4f3U
      - aws-secretsmanager:gestaopagamentoscash-gestaodividas-awssae1aurmy-hom-RDSInstanceUserSecret-k4f3U
      - aws-secretsmanager:gestaopagamentoscash-gestaodividas-awssae1aurmy-hom-RDSInstancePasswordSecret-k4f3U

  cloud:
    aws:
      region:
        static: sa-east-1

datasource:
  url-writer: ${gestaopagamentoscash-gestaodividas-awssae1aurmy-hom-RDSInstanceEndpointSecret-k4f3U}
  url-reader: ${gestaopagamentoscash-gestaodividas-awssae1aurmy-hom-RDSInstanceReaderEndpointSecret-k4f3U}
  username:   ${gestaopagamentoscash-gestaodividas-awssae1aurmy-hom-RDSInstanceUserSecret-k4f3U}
  password:   ${gestaopagamentoscash-gestaodividas-awssae1aurmy-hom-RDSInstancePasswordSecret-k4f3U}

spring:
  datasource:
    driver-class-name: software.amazon.jdbc.Driver
    url: jdbc:aws-wrapper:mysql://${datasource.url-writer}:3306/<db>
    username: ${datasource.username}
    password: ${datasource.password}
    hikari:
      maximum-pool-size: 15
      minimum-idle: 3
      connection-timeout: 30000
      validation-timeout: 5000
      idle-timeout: 600000
      max-lifetime: 1800000
      data-source-properties:
        wrapperPlugins: readWriteSplitting,failover
        readWriteSplitting.readerEndpoint: ${datasource.url-reader}
        cachePrepStmts: true
        prepStmtCacheSize: 250
        prepStmtCacheSqlLimit: 2048
        useServerPrepStmts: true
        useUnicode: true
        characterEncoding: utf8

  jpa:
    hibernate:
      ddl-auto: none
    properties:
      hibernate:
        dialect: org.hibernate.dialect.MySQLDialect
        jdbc.time_zone: UTC
```

**Explicações-chave**  
- **`spring.config.import`**: importa os segredos como propriedades cujo **nome é o próprio segredo**.  
- **`datasource.*` (seção auxiliar)**: apenas normaliza os nomes para compor a URL final.  
- **Wrapper + plugins**: `readWriteSplitting` faz o split via `readOnly`; `failover` lida com troca de instância.  
- **MySQL props**: ganhos de latência/CPU com cache de PS.  
- **Hibernate**: `ddl-auto: none` em hom/prd; `UTC` para consistência de horário.

---

## Como o split funciona no código

```java
@Service
@RequiredArgsConstructor
public class DividasService {

  private final DividaRepository repo;

  @Transactional // -> WRITER (padrão)
  public void registrarPagamento(Pagamento p) {
    // INSERT/UPDATE ...
  }

  @Transactional(readOnly = true) // -> READER (split automático pelo wrapper)
  public List<Divida> listarResumo(Filtro f) {
    return repo.findResumo(f);
  }
}
```

**Boas práticas**  
- Marque `readOnly = true` **apenas** onde não há dependência de “ler o que acabou de gravar”.  
- Leituras logo após escrita no mesmo fluxo → **permaneça no writer** (sem `readOnly`).

---

## RDS Proxy — combinação correta

- O RDS Proxy **não** faz split sozinho. Crie **dois endpoints no proxy**:  
  - **writer** (read/write) → configure em `spring.datasource.url`  
  - **reader** (read-only) → configure em `readWriteSplitting.readerEndpoint`  
- Benefícios: *warm pool*, reconexão estável e gerenciamento centralizado, **preservando** o split do wrapper.

---

## Observabilidade, validação e troubleshooting

- **Métricas (Actuator/Micrometer)**: `hikaricp.connections.active/pending/acquire/timeout`.  
- **Logs de teste**: habilite DEBUG para o pacote do wrapper em hom/dev e confirme que `readOnly` -> **reader**.  
- **Sinais de ajuste**:  
  - `acquire` alto / timeouts → pool curto (ou DB saturado).  
  - CPU/`DatabaseConnections` no Aurora altos → pool exagerado (reduza) ou otimize SQL/índices.  
- **Lag esperado** no reader: réplicas são eventualmente consistentes → use writer quando precisar de *read-your-writes*.

---

## Segurança (IAM) e rede

- **IAM Role** da máquina/pod (EKS/ECS/EC2) em vez de chaves estáticas.  
- **Política mínima**: `secretsmanager:GetSecretValue` e `DescribeSecret` apenas para os segredos usados.  
- **Rede**: Security Groups abrindo **3306** somente entre app ↔ RDS/Proxy.

---

## Checklist de implantação

1. Dependências adicionadas (`mysql-connector-j`, `aws-advanced-jdbc-wrapper`, opcional `spring-cloud-aws-starter-secrets-manager`).  
2. Segredos referenciados via `spring.config.import`.  
3. `driver-class-name` alterado para `software.amazon.jdbc.Driver`.  
4. URL alterada para `jdbc:aws-wrapper:mysql://<writer>:3306/<db>`.  
5. `wrapperPlugins=readWriteSplitting,failover` e `readWriteSplitting.readerEndpoint` definidos.  
6. `@Transactional(readOnly = true)` aplicado nas consultas elegíveis.  
7. Métricas/Logs verificados (valide o split).  
8. Pool calibrado por dados (Lei de Little + carga).  
9. Revisado `ddl-auto`, `dialect` e `UTC`.  
10. IAM/SGs revisados.

---

## Apêndice: Segredo único JSON (opcional)

Para simplificar, você pode consolidar num **único segredo** (ex.: `/hom/gestaodividas/db`) contendo:

```json
{
  "datasource.url-writer": "awssae1-aurora-writer.cluster-...amazonaws.com",
  "datasource.url-reader": "awssae1-aurora-reader.cluster-ro-...amazonaws.com",
  "datasource.username": "app_user",
  "datasource.password": "S3cr3t!"
}
```

E então:

```yaml
spring:
  config.import: aws-secretsmanager:/hom/gestaodividas/db
datasource:
  url-writer: ${datasource.url-writer}
  url-reader: ${datasource.url-reader}
  username:   ${datasource.username}
  password:   ${datasource.password}
```

> **Vantagem**: um único `spring.config.import`. **Desvantagem**: precisa migrar os segredos atuais para o novo JSON.

---

**Fim.**
