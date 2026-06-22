# Cluster Distribuído: Algoritmo Bully e Replicação

Este projeto implementa uma aplicação distribuída baseada no algoritmo de eleição de líder (Bully) integrado a um mecanismo de replicação de estado (Primary-Backup). O cluster atua como um orquestrador que recebe tarefas de um cliente, gerencia uma fila no líder e distribui o processamento entre os nós seguidores. A comunicação entre os processos é feita via Berkeley Sockets.

## Configuração Inicial

Antes de executar, aplique permissão de execução aos scripts do projeto:

```bash
chmod +x scripts/*.sh

```

---

## Opção 1: Execução Local em Múltiplos Terminais (RECOMENDADO)

**Pré-requisito:** Compilador Zig 0.15.2.
Caso não o possua, instale-o localmente na pasta do projeto utilizando o script abaixo:

```bash
./scripts/zig.sh

```

### Instruções de Execução

1. **Gere a configuração do cluster:**
```bash
./scripts/setup.sh

```


2. **Inicie os nós:**
Abra terminais independentes para cada nó e execute o script de inicialização passando o ID (exemplo para 3 nós):
```bash
# Terminal 1
./scripts/run.sh 1

```


```bash
# Terminal 2
./scripts/run.sh 2

```


```bash
# Terminal 3
./scripts/run.sh 3

```


3. **Inicie o cliente gerador de tarefas:**
Em um novo terminal, execute:
```bash
./scripts/start_tasks.sh

```



### Testes de Cenários de Falha

* **Queda do Líder:** Identifique o terminal executando o líder atual e pressione `Ctrl+C` para encerrar o processo. Os nós restantes detectarão a ausência via timeout, realizarão uma nova eleição e o novo líder recuperará a fila de tarefas utilizando o estado replicado.
* **Transferência de Fila (Handover):** Com o cluster operando normalmente, abra um novo terminal e inicie um nó com um ID superior ao do líder atual (ex: `./scripts/run.sh 9`). O líder atual detectará o novo nó, enviará a fila ativa via mensagem direta (`sync_queue`) e passará a atuar como seguidor.

---

## Opção 2: Execução via Docker

A execução via Docker é menos recomendada pois os logs são disparados todos no mesmo terminal, dificultando visualização, além de tornar mais complexa a simulação de falhas, é sugerido utilizar dessa forma apenas no caso de falha na configuração do zig 0.15.2

### Instruções de Execução

1. **Construa a imagem Docker:**
```bash
sudo docker build -t bully-cluster .

```


2. **Inicie o cluster:**
Execute o contêiner nomeado `cluster-test`. O Makefile interno subirá os processos e exibirá os logs multiplexados.
```bash
sudo docker run -it --init --name cluster-test --rm bully-cluster

```



### Testes de Cenários de Falha

Para simular falhas em processos executados em background no contêiner:

1. Abra um segundo terminal físico na máquina hospedeira e acesse o contêiner:
```bash
sudo docker exec -it cluster-test bash

```


2. Encerre o processo associado ao líder atual (por padrão, o nó 9 após a inicialização):
```bash
pkill -f "main 9"

```


3. Retorne ao terminal principal do Docker para observar o comportamento de reeleição e recuperação de estado pelos nós sobreviventes. Para encerrar o contêiner, utilize `Ctrl+C`.
