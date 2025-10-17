# Aplicação Spring Boot 3.4.5 com AWS Aurora MySQL e LocalStack

Este projeto demonstra uma aplicação Spring Boot 3.4.5 com Java 21, integrando-se a um banco de dados MySQL (simulando AWS Aurora MySQL) e utilizando LocalStack para ambiente de desenvolvimento local. A aplicação expõe um endpoint REST para gerenciamento de usuários.

## 1. Visão Geral

O objetivo desta aplicação é fornecer um exemplo prático de como desenvolver uma API RESTful em Spring Boot, conectando-se a um banco de dados MySQL, com foco em boas práticas de mercado e utilizando ferramentas para simulação de serviços AWS localmente.

### Tecnologias Utilizadas:

*   **Java 21**: Linguagem de programação.
*   **Spring Boot 3.4.5**: Framework para construção de aplicações Java.
*   **Spring Data JPA**: Para persistência de dados.
*   **MySQL Connector/J**: Driver JDBC para MySQL.
*   **HikariCP**: Pool de conexões de banco de dados de alta performance.
*   **Lombok**: Para reduzir código boilerplate.
*   **Maven**: Ferramenta de gerenciamento de projetos e dependências.
*   **Docker & Docker Compose**: Para orquestração de contêineres (MySQL e LocalStack).
*   **LocalStack**: Simula serviços AWS localmente, como RDS (para Aurora MySQL).

## 2. Pré-requisitos

Certifique-se de ter as seguintes ferramentas instaladas em seu ambiente de desenvolvimento:

*   **Java Development Kit (JDK) 21**
*   **Apache Maven 3.6+**
*   **Docker Desktop** (inclui Docker Engine e Docker Compose)

## 3. Estrutura do Projeto

```
spring-aurora-app/
├── pom.xml
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/example/auroraapp/
│   │   │       ├── AuroraAppApplication.java
│   │   │       ├── User.java
│   │   │       ├── UserRepository.java
│   │   │       └── UserController.java
│   │   └── resources/
│   │       ├── application.properties
│   │       ├── application-local.properties
│   │       └── application-prod.properties
│   └── test/
│       └── java/
│           └── com/example/auroraapp/
│               └── UserControllerTest.java
├── docker-compose.yml
├── start-local-env.sh
└── stop-local-env.sh
```

*   `pom.xml`: Contém as dependências do projeto e configurações do Maven.
*   `AuroraAppApplication.java`: Classe principal da aplicação Spring Boot.
*   `User.java`: Entidade JPA que representa um usuário no banco de dados.
*   `UserRepository.java`: Interface de repositório para operações CRUD com a entidade `User`.
*   `UserController.java`: Controlador REST que expõe endpoints para `User`.
*   `application.properties`: Configuração base compartilhada entre os perfis, com parâmetros JPA, HikariCP e integração com AWS Secrets Manager.
*   `application-<profile>.properties`: Especificam ajustes por perfil (`local` e `prod`) para endereços, credenciais e ativação do Secrets Manager.
*   `UserControllerTest.java`: Testes unitários para o controlador REST.
*   `docker-compose.yml`: Define os serviços Docker para MySQL e LocalStack.
*   `start-local-env.sh`: Script para iniciar o ambiente local (MySQL e LocalStack).
*   `stop-local-env.sh`: Script para parar o ambiente local.

## 4. Configuração do Ambiente Local com LocalStack

Para simular o ambiente AWS Aurora MySQL localmente, utilizamos Docker Compose para orquestrar um contêiner MySQL e um contêiner LocalStack.

### 4.1. Iniciar o Ambiente Local

Navegue até o diretório raiz do projeto (`spring-aurora-app`) e execute o script para iniciar os serviços:

```bash
./start-local-env.sh
```

Este script:
1.  Inicia os contêineres `mysql` e `localstack` definidos no `docker-compose.yml` em modo *detached* (`-d`).
2.  O contêiner `mysql` é configurado com um banco de dados `aurora_db` e usuário `root` com senha `password`, conforme `application.properties`.
3.  O contêiner `localstack` simula serviços AWS, incluindo RDS, que pode ser usado para futuras integrações AWS (embora para este exemplo, a conexão direta com o MySQL seja suficiente para a demonstração do Aurora compatível).
4.  Aguardará 30 segundos para garantir que os serviços estejam totalmente inicializados.

### 4.2. Parar o Ambiente Local

Para parar e remover os contêineres, execute:

```bash
./stop-local-env.sh
```

## 5. Configuração da Aplicação

A aplicação utiliza perfis do Spring Boot para separar a configuração local da configuração voltada ao Aurora em produção.

### Configuração base (`application.properties`)

```properties
spring.application.name=aurora-app

spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

spring.jpa.hibernate.ddl-auto=validate
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQL8Dialect

spring.datasource.hikari.maximum-pool-size=${DB_MAX_POOL_SIZE:10}
spring.datasource.hikari.minimum-idle=${DB_MIN_IDLE:5}
spring.datasource.hikari.connection-timeout=${DB_CONNECTION_TIMEOUT:30000}
spring.datasource.hikari.idle-timeout=${DB_IDLE_TIMEOUT:600000}
spring.datasource.hikari.max-lifetime=${DB_MAX_LIFETIME:1740000}
spring.datasource.hikari.validation-timeout=${DB_VALIDATION_TIMEOUT:5000}

spring.cloud.aws.secretsmanager.enabled=false
spring.cloud.aws.secretsmanager.default-context=aurora-app
spring.cloud.aws.secretsmanager.profile-separator=_
spring.cloud.aws.secretsmanager.prefix=/config
```

Essas configurações atendem às recomendações para produção: validação de schema em vez de atualizações automáticas, SQL oculto em logs e parâmetros do Hikari personalizáveis via variáveis de ambiente.

### Perfil local (`application-local.properties`)

Usado durante o desenvolvimento com o banco da `docker-compose`:

```properties
spring.config.activate.on-profile=local

spring.datasource.url=jdbc:mysql://localhost:3306/aurora_db
spring.datasource.username=root
spring.datasource.password=password

spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true

spring.cloud.aws.secretsmanager.enabled=false
```

Ative com `--spring.profiles.active=local` ou definindo a variável de ambiente `SPRING_PROFILES_ACTIVE=local`.

### Perfil de produção (`application-prod.properties`)

Voltado para instâncias Aurora gerenciadas:

```properties
spring.config.activate.on-profile=prod

spring.datasource.url=${AURORA_DB_URL:}
spring.datasource.username=${AURORA_DB_USERNAME:}
spring.datasource.password=${AURORA_DB_PASSWORD:}

spring.cloud.aws.region.static=${AWS_REGION:us-east-1}
spring.cloud.aws.secretsmanager.enabled=true
spring.cloud.aws.secretsmanager.default-context=aurora-app
spring.cloud.aws.secretsmanager.prefix=/config
spring.cloud.aws.secretsmanager.profile-separator=_
```

Quando o perfil `prod` está ativo, o Spring Cloud AWS Secrets Manager é habilitado e pode preencher automaticamente as propriedades do datasource a partir de segredos nomeados como `aurora-app_prod`. Caso a aplicação seja executada fora da AWS, é possível fornecer as mesmas variáveis de ambiente (`AURORA_DB_URL`, `AURORA_DB_USERNAME`, `AURORA_DB_PASSWORD`).

**Boas Práticas de Configuração:**

*   **HikariCP**: Ajuste o pool (`maximum-pool-size`, `minimum-idle`, `max-lifetime`, etc.) conforme os limites da instância Aurora. Os valores padrão contemplam o SLA comum (tempo de vida máximo inferior ao `wait_timeout`).
*   **Migrações de banco**: Em produção use ferramentas como Flyway/Liquibase e mantenha `ddl-auto=validate`.
*   **Segredos gerenciados**: Armazene credenciais em Secrets Manager ou Parameter Store para evitar segredos codificados na aplicação.

## 6. Executando a Aplicação

Certifique-se de que o ambiente local (MySQL e LocalStack) esteja em execução (`./start-local-env.sh`).

1.  **Compilar o projeto:**
    Navegue até o diretório raiz do projeto (`spring-aurora-app`) e execute:
    ```bash
    ./mvnw clean install -DskipTests
    ```
    O `-DskipTests` é usado para pular a execução dos testes durante a compilação, o que é recomendado em ambientes de CI/CD ou quando você deseja apenas compilar o projeto rapidamente. Os testes unitários são fornecidos e devem ser executados separadamente.

2.  **Executar a aplicação Spring Boot:**
    ```bash
    ./mvnw spring-boot:run
    ```
    A aplicação será iniciada na porta padrão 8080.

## 7. Endpoints REST

A aplicação expõe os seguintes endpoints REST para a entidade `User`:

| Método HTTP | Endpoint       | Descrição                                  | Requisição (Exemplo)                                    | Resposta (Exemplo)                                      |
| :---------- | :------------- | :----------------------------------------- | :------------------------------------------------------ | :------------------------------------------------------ |
| `GET`       | `/api/users`   | Retorna todos os usuários.                 | `curl http://localhost:8080/api/users`                  | `[ { "id": 1, "name": "John Doe", "email": "john@example.com" } ]` |
| `GET`       | `/api/users/{id}` | Retorna um usuário pelo ID.                | `curl http://localhost:8080/api/users/1`                | `{ "id": 1, "name": "John Doe", "email": "john@example.com" }` |
| `POST`      | `/api/users`   | Cria um novo usuário.                      | `curl -X POST -H "Content-Type: application/json" -d '{"name": "Jane Doe", "email": "jane@example.com"}' http://localhost:8080/api/users` | `{ "id": 2, "name": "Jane Doe", "email": "jane@example.com" }` |
| `PUT`       | `/api/users/{id}` | Atualiza um usuário existente pelo ID.     | `curl -X PUT -H "Content-Type: application/json" -d '{"name": "Jane Smith", "email": "jane.smith@example.com"}' http://localhost:8080/api/users/2` | `{ "id": 2, "name": "Jane Smith", "email": "jane.smith@example.com" }` |
| `DELETE`    | `/api/users/{id}` | Deleta um usuário existente pelo ID.       | `curl -X DELETE http://localhost:8080/api/users/1`      | `(No Content)`                                          |

## 8. Testes

Testes unitários para o `UserController` são fornecidos em `src/test/java/com/example/auroraapp/UserControllerTest.java`. Para executá-los, utilize:

```bash
mvn test
```

## 9. Considerações Finais

Este projeto serve como um ponto de partida para aplicações Spring Boot com integração MySQL/Aurora e ambiente local com LocalStack. Para um ambiente de produção, considere:

*   **Segurança**: Implementar autenticação e autorização (ex: Spring Security).
*   **Observabilidade**: Adicionar monitoramento, logging e tracing.
*   **Migrações de DB**: Utilizar Flyway ou Liquibase para gerenciar o schema do banco de dados.
*   **Otimização**: Ajustar as configurações do HikariCP e do Aurora MySQL para o perfil de carga específico da sua aplicação.
*   **CI/CD**: Integrar em um pipeline de Continuous Integration/Continuous Deployment.

---

**Autor:** Manus AI
**Data:** 17 de Outubro de 2025
