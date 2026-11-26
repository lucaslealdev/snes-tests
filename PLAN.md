# Plano: ROM de testes unificada (65C816 + SPC-700)

Objetivo: juntar `cputest` e `spctest` numa só ROM com interface moderna, menu de seleção por
checkboxes (tudo marcado por padrão), opção para iniciar os testes, execução sequencial e
automática, e um relatório final em inglês, em linguagem natural, descrevendo os testes que falharam.

## Decisões tomadas

| Tema | Decisão |
|---|---|
| Estado persistente | Tudo numa faixa reservada da WRAM (~16 KB, por exemplo `$7F:C000`–`$7F:FFFF`), com magic e checksum. A ROM não tem SRAM. |
| Teste da CPU travado | Recuperação por reset. Magic válido no boot significa reset no meio da execução: o teste atual vira "hang" e a execução retoma no seguinte. Magic inválido significa power-on: começa do zero. |
| SPC travado | Watchdog no 65C816 reenvia o `.spc` e retoma no teste seguinte. Se a IPL não responder, registra "SPC unresponsive", marca os SPC restantes como não executados e segue. |
| Checkboxes | Um por grupo de instrução (cada função `*_tests()`, ~150 itens), em categorias CPU/SPC recolhíveis |
| Filtros | 3 filtros globais: Emulation mode (E=1), Undocumented, Decimal. Todos ligados por padrão. Na CPU valem teste a teste; no SPC valem por grupo (`daa`/`das`/`div` = Undocumented). |
| Lembrar a seleção | Não: ao ligar, tudo vem marcado |
| Ordem de execução | SPC primeiro, depois a CPU |
| Seleção vazia | "Start tests" fica desabilitado e aparece "No tests selected" |
| Depois do relatório | Volta ao menu com a mesma seleção e permite rodar de novo sem reset. Reset na tela de relatório mostra o menu com a seleção anterior, sem auto-start. |
| Auto-start | 10 s, só na primeira entrada do menu depois do power-on. Qualquer botão cancela até o próximo power-on. |
| Onde fica o relatório | Só na tela da ROM, sem exportação em texto |
| Detalhe de cada falha | Número, grupo, instrução, modo M/X/E, entradas, e a **primeira** verificação que falhou (real × esperado) |
| ROMs antigas | Congeladas numa tag e release `legacy-v1` antes de começar. Depois, os harnesses antigos e o `--basic` saem do build. |
| Emulador da automação | Mesen2 (`--testrunner` + Lua) |
| Critério de aceite | 100% de aprovação no Mesen2, e a build com falhas plantadas reporta exatamente essas falhas. Falhas conhecidas do Mesen2 vão para uma lista de esperadas. |
| Visual | Completo: Mode 1, fonte nova, paleta escura, gradiente HDMA, cursor em sprite, barras de progresso (sem sons de UI) |

## O que o código atual impõe

- **Os testes da CPU apagam quase todo o estado.** Os testes do `cputest` escrevem na WRAM
  (`$7E`/`$7F`), em `$1000`–`$100C`, no stack e em D/DBR. O estado do runner só pode ficar numa
  faixa da WRAM que uma auditoria prove que nenhum teste toca.
- **As duas ROMs param na primeira falha.** O `cputest` espera o botão A em `fail`. O `spctest`
  trava os dois processadores (`fail: .end: bra .end`). Para rodar tudo sozinho, os dois precisam
  registrar a falha e seguir.
- **Não dá para montar um relatório em linguagem natural só com o que existe hoje.** Os valores
  esperados viram comparações imediatas (`cpx #$1234`). O SPC só devolve A/X/Y/PSW e não diz qual
  verificação falhou. Os geradores precisam emitir esses metadados.
- **Os testes da CPU rodam com NMI e IRQ desligados.** Um teste que trava a 65C816 não pode ser
  interrompido sem alterar a pilha dos testes. Por isso a recuperação é por reset.
- **O banco 0 está cheio.** Ele tem `TESTS_IN_BANK0 = 230`, `TEST_DATA` fixo em `$00FFA0`, os
  vetores e os handlers. O menu e o relatório precisam ir para bancos próprios.
- **Ferramentas:** `ca65` e `ld65` estão instalados. O `spcasm` e o Mesen2 ainda não.

---

## Etapa 0 — Preparação e baseline

1. **Fechar o trabalho em andamento:** commitar as mudanças de `-basic`/`-full` em `main.asm` e
   `make_cpu_tests.py`.
2. **Congelar as ROMs antigas:** montar `cputest-full.sfc`, `cputest-basic.sfc` e `spctest.sfc`,
   criar a tag `legacy-v1` e publicar uma release com as 3 ROMs. Depois, criar a branch
   `unified-rom`.
3. **Instalar as ferramentas:** `spcasm` e Mesen2, que também roda sem interface para automação.
4. **Registrar o baseline:** rodar as 3 ROMs antigas no Mesen2 (no `cputest`, um Lua aperta A em
   cada falha). Se algum teste falhar, registrar essas falhas em `expected-failures.txt` no repo.

## Etapa 1 — Estrutura e build unificado

1. **Reorganizar o repositório:**
   - `harness/` com o código comum: vídeo, texto, joypad, menu, runner e relatório.
   - `cputest/` e `spctest/` ficam só com os geradores e o código específico de cada CPU.
   - `assets/` com fonte, paleta e gráficos gerados por script.
   - Remover os harnesses antigos (`cputest/main.asm`, `spctest/spctest.asm`) e o modo `--basic`
     do gerador. Eles continuam disponíveis na tag `legacy-v1`.
2. **Criar o `snes-tests.cfg`:** LoROM de 512 KB a 1 MB, sem SRAM.
   - Bancos 1 a 7 para os testes da CPU, como hoje.
   - Bancos separados para os `.spc`, para o menu e relatório, e para as tabelas de metadados.
   - `TEST_DATA` continua em `$00FFA0` e os handlers BRK/COP em `$1000`–`$100C`.
   - Segmento da WRAM reservada para o estado do runner, fora de qualquer área usada pelos testes.
3. **Reescrever o Makefile da raiz:** gerar os dois conjuntos, montar os `.spc` e linkar um único
   `snes-tests.sfc`. Incluir `clean` de verdade e `package`.
4. **Tirar os valores fixos espalhados:** o número de arquivos SPC (hoje 3, repetido no Makefile,
   no `.asm` e no `.cfg`) passa a vir de um `.inc` gerado. Assim, passar de 1500 testes deixa de
   exigir edição manual.
5. **Liberar espaço no banco 0:** reduzir `TESTS_IN_BANK0` conforme o que sobrar ali.

## Etapa 2 — Metadados nos geradores

1. **Grupos:** cada função `*_tests()` vira um grupo com nome legível ("ADC (binary)", "MVN",
   "Branches"…), CPU, tags e a faixa de testes. Saem daí `groups-cpu.inc` e `groups-spc.inc`:
   tabela com nome, primeiro teste, quantidade e endereço de entrada.
2. **Tags por teste (CPU):** cada teste recebe bits `emulation` (E=1, o antigo "advanced"),
   `undocumented` (os que usam `comment=UNDOCUMENTED_COMMENT`) e `decimal`. A ROM inclui todos os
   testes e os filtros do menu decidem o que roda.
3. **Tags por grupo (SPC):** `daa`, `das` e `div` ficam marcados como grupos `undocumented`.
4. **Registro por teste**, em tabela na ROM (~10 bytes por teste):
   - Instrução (índice para uma tabela de strings sem repetição).
   - Modo: M, X, E e o modo do SPC.
   - Valores de entrada.
   - Tags.
5. **Stubs de falha:** cada `bne @to_fail` vai para um stub próprio que grava o **ID da
   verificação** (registrador A, X, Y, P, S, D, DBR ou memória no endereço N) e o **valor
   esperado** antes de pular para `fail`. Os valores esperados não precisam de tabela na ROM.
6. **Manter a numeração:** CPU e SPC seguem numeradas cada uma a partir de 0, e o relatório mostra
   `CPU #0123` e `SPC #0412`. As referências antigas e os `tests-*.txt` continuam valendo.
7. **Estimar o tamanho:** medir o espaço das tabelas e dos stubs e, se precisar, compactar
   (strings deduplicadas, entradas só quando diferem do padrão).

## Etapa 3 — Mapa de memória e estado persistente

1. **Auditar os acessos (bloqueante para a etapa 4):** escrever um script que varre os dois
   geradores e confirma que nenhum teste toca a faixa reservada da WRAM. A auditoria cobre:
   - `mem_*`/`emem_*`/`memw_*`/`ememw_*`.
   - `s=`, `d=`, `dbr=` e a região de pilha que cada teste pode usar.
   - Blocos movidos por `MVN`/`MVP`.
   - Endereços indiretos montados com D, DBR e índices.
   - Os mirrors da WRAM no banco 0.
2. **Layout da faixa reservada da WRAM:**
   - Magic, versão e checksum.
   - Bitmask de grupos selecionados e estado dos filtros da execução atual.
   - Estado do runner: fase (menu, rodando SPC, rodando CPU, relatório), próximo teste, contadores.
   - Flag "auto-start já usado" desde o power-on.
   - Lista de falhas: número, ID da verificação, valor real e valor esperado. Até ~1000 falhas
     detalhadas; acima disso, só contagem por grupo.
3. **Boot:**
   - Magic ou checksum inválido significa power-on: estado zerado, tudo marcado, auto-start ativo.
   - Fase "rodando": o teste atual é registrado como "hang" e a execução retoma no seguinte.
   - Fase "relatório" ou "menu": mostra o menu com a seleção anterior, sem auto-start.

## Etapa 4 — Runner sequencial e automático

1. **Máquina de estados:** Título → Menu → Rodar SPC → Rodar CPU → Relatório → Menu.
2. **Lado SPC-700**, primeiro (`spc_common.inc` e o protocolo mudam juntos, documentados no topo
   do harness):
   - O SPC recebe o número do teste inicial e usa uma tabela de saltos gerada para começar em
     qualquer grupo. O runner só envia os grupos marcados e não excluídos pelo filtro Undocumented.
   - A falha vira `call`: o SPC envia número, PSW, A, X, Y, o ID da verificação e o valor
     esperado, espera o ack e segue para o próximo teste.
   - Um watchdog no 65C816 detecta SPC travado (sem mudança de número de teste por N frames).
     Nesse caso o runner registra "hang", reenvia o `.spc` e retoma no teste seguinte. Se a IPL
     não responder, o runner registra "SPC unresponsive", marca os SPC restantes como não
     executados e passa para a CPU.
   - O SPC volta para a IPL ROM no fim, para permitir rodar de novo sem reset.
3. **Lado 65C816:**
   - O runner percorre a `tests_table` e pula cada teste cujo grupo não está marcado ou cujas
     tags um filtro exclui. `init_test` é ajustado para aceitar esses saltos, e a checagem de
     "ordem inválida" continua pegando saltos errados.
   - `fail` grava a falha na WRAM reservada, reinicializa o estado (S, D, DBR, E=0) e segue sem
     esperar botão.
   - "Invalid test order" e BRK/COP inesperados (hoje um `STP` em `$1000`) viram falhas
     registradas, e a execução continua no próximo teste.
   - NMI e IRQ desligados durante os testes, como hoje, com o placar atualizado por polling de
     `$4210` a cada N testes.
   - Um teste que trava a CPU só é recuperado por reset (ver a etapa 3.3).
4. **Placar ao vivo:** totais de aprovados, reprovados e pulados por CPU, sempre na WRAM reservada.

## Etapa 5 — Interface moderna

1. **Base gráfica:**
   - Mode 1, com BG1 para o conteúdo e BG3 para o cabeçalho e o rodapé.
   - Fonte nova em 2 ou 4 bpp gerada por script, paleta escura com uma cor de destaque.
   - Gradiente de fundo por HDMA e cursor animado em sprite.
   - Sem sons de UI.
2. **Framework de UI:** NMI com fila de atualização de VRAM por DMA (só fora da execução dos
   testes), leitura do joypad com auto-repeat, e componentes reutilizáveis (lista rolável,
   checkbox, barra de progresso, caixa de texto).
3. **Tela de seleção:**
   - No topo, os 3 filtros globais: "Emulation mode (E=1)", "Undocumented behavior" e "Decimal
     mode". Todos vêm ligados.
   - Árvore com "SPC-700" e "65C816 CPU" como categorias recolhíveis, e os grupos como itens com
     checkbox. **Tudo vem marcado por padrão.**
   - Atalhos: Y marca ou desmarca o item, X marca ou desmarca a categoria, L/R troca de página.
     Presets "All" e "None".
   - Contador ao vivo de testes que vão rodar (grupos e filtros aplicados).
   - Item **▶ Start tests** fixo no fim. Start também inicia de qualquer lugar. Com zero testes,
     o item fica cinza com "No tests selected" e Start não faz nada.
   - **Auto-start:** só na primeira entrada do menu depois do power-on. Contagem regressiva de
     10 s no rodapé; ao chegar a zero, os testes começam com tudo marcado. Qualquer botão cancela
     a contagem até o próximo power-on.
4. **Tela de execução:** barra de progresso geral e por CPU, grupo e teste atual, aprovados,
   reprovados e pulados, e tempo decorrido.
5. **Tela de relatório:** resumo no topo, lista rolável das falhas, A abre o detalhe de cada uma, e
   uma opção "Back to menu" volta ao menu com a mesma seleção.

## Etapa 6 — Relatório em inglês (linguagem natural)

1. **Composição das frases na ROM**, por templates preenchidos com a tabela por teste e os dados
   da falha (ID da verificação, real e esperado). Exemplos:
   - *"CPU test #0123 (ADC) — `ADC ($10),Y` with 8-bit accumulator, 16-bit index, native mode.
     Inputs: A=$1234 X=$3456 Y=$5678 P=$31. A was $35 but $36 was expected."*
   - *"P was $02 but $00 was expected: the Zero (Z) flag was set but should be clear."* (cada bit
     de P diferente na verificação de P vira uma frase com o nome da flag)
   - *"Memory at $7E1234 was $00; expected $FF."*
   - *"CPU test #0456 never finished (hang) — testing resumed after reset."*
   - *"SPC test #0412 stopped responding (hang) — the SPC program was reloaded and testing
     resumed."*
   - *"The SPC-700 stopped responding; 312 SPC tests were not run."*
   - Nota extra quando o teste cobre comportamento não documentado.
   - Só a primeira verificação que falhou é descrita.
2. **Resumo:** *"4,812 of 4,820 tests passed. 8 failures in 3 groups: MVN (5), PLB (1), SPC DIV
   (2)."* Mais uma linha com os testes pulados por filtro ou por grupo desmarcado, e um aviso se
   o limite de falhas detalhadas foi atingido.
3. **Só na tela:** o relatório é exibido apenas pela ROM, sem exportação em texto. Os detalhes
   extras de cada teste continuam nos `tests-*.txt` gerados no build.

## Etapa 7 — Automação e verificação

1. **Execução sem interface:** a ROM inicia sozinha pelo auto-start. Um script Lua para o Mesen2
   (`--testrunner`):
   - Espera a fase "relatório" na WRAM reservada ou o fim de um tempo limite total.
   - Se o número do teste parar de mudar por um tempo, aplica um reset para acionar a retomada.
   - No fim, lê os contadores e a lista de falhas na memória, imprime um resumo no log e sai com
     código 0 ou 1.
2. **Critério de aceite:** a ROM unificada passa 100% no Mesen2, descontando as falhas em
   `expected-failures.txt`. O CI falha se aparecer uma falha fora da lista, ou se uma falha
   esperada sumir.
3. **Testes do próprio harness:** uma build de depuração com falhas plantadas (um teste com valor
   esperado errado, um com salto errado, um que trava a CPU e um SPC que trava). O aceite exige que
   o relatório traga exatamente essas falhas, com o texto certo.
4. **Testes dos geradores e das tabelas:** testes Python simples para consistência de grupos,
   tags, contagens e IDs de verificação, mais o script de auditoria da etapa 3.
5. **CI:** GitHub Actions monta a ROM, roda no Mesen2 sem interface e publica a ROM como artefato
   (o resultado fica no log e no código de saída). `make package` gera o zip novo, só com a ROM
   unificada.
6. **Hardware real**, quando possível: rodar a ROM numa flashcart, porque o Mesen2 não pega tudo.
   Confirmar que a WRAM reservada sobrevive ao reset no console.

## Etapa 8 — Documentação e limpeza

1. Atualizar o README: como usar o menu, filtros, controles, auto-start, o que fazer se a CPU
   travar (reset) e onde baixar as ROMs antigas (release `legacy-v1`).
2. Atualizar o CLAUDE.md: estrutura nova, layout da WRAM reservada, protocolo SPC novo, tags e
   stubs de falha.

---

## Riscos principais

- **Espaço no banco 0 e em `TEST_DATA`:** o menu não pode empurrar os endereços fixos de que os
  testes dependem.
- **Testes que sobrescrevem a WRAM reservada:** a auditoria da etapa 3 é obrigatória antes da
  etapa 4. Uma escrita não detectada corrompe o estado e só aparece como checksum inválido.
- **WRAM no reset:** a WRAM costuma sobreviver ao reset, mas isso precisa ser confirmado no
  Mesen2 e no hardware real (etapa 7.6).
- **Recuperação do SPC travado:** o reenvio só funciona se a IPL ainda responder. Se não
  responder, os SPC restantes ficam como não executados.
- **Tamanho dos metadados e stubs:** como o relatório só existe na tela, tudo o que ele descreve
  precisa caber na ROM. Se ficar grande demais, compactar as tabelas (etapa 2.7) ou ampliar a ROM
  para 1 MB ou mais.
