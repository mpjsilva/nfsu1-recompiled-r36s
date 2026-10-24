# Need for Speed: Underground (NFSU1) — port para o R36S

Uma recompilação estática do **Need for Speed: Underground** (PC, `SPEED.EXE`, 2003) para o **R36S** e outros
portáteis com RK3326. Ele roda sobre o runtime do port do NFSU2 deste repositório: o código do jogo é convertido
a partir do próprio executável do NFSU1, e a camada Direct3D 9 → OpenGL ES 2.0, os controles, o áudio e a camada
da API do Windows são os mesmos do NFSU2. Chave de build: `NFS_GAME_U1`.

English: [README.md](README.md).

## Situação

Jogável do começo ao fim no R36S: tela de título, criação de perfil, menus, Corrida Individual (testada no modo
Circuito), escolha de carro e pista, e corridas com HUD, rivais e direção analógica.

| | |
|---|---|
| Menus | 30 FPS (limite) |
| Corridas | cerca de 15–19 FPS; os módulos de desempenho do NFSU2 ainda não foram portados para o NFSU1 |
| Efeitos sonoros | funcionando (motor, pneus, menus) |
| Música | **pelo player próprio do port** (seus arquivos OGG/MP3, veja abaixo) |
| Som ambiente e falas | **ausentes**: o player de streams do jogo nunca inicia (problema em aberto) |
| Imagem | só 4:3 (ainda sem widescreen) |

Resolução interna: os menus são desenhados em 800×600 e reduzidos para a tela de 640×480; ao começar a corrida
o jogo reinicia o vídeo em 640×480, desenhado 1:1.

## O que você precisa

Nenhum arquivo do jogo vem junto. Use a sua cópia do NFSU1 para PC.

* `SPEED.EXE`: 3.178.496 bytes, SHA-256
  `35654f401383be9af0dbff0d11a92220a17579a01030005de6943e63e03f460f`
  (MD5 `22c731fe0c0c41fe14ce80b728b6cbe0`). Outras versões têm o código em outros endereços e não rodam.
  Se na sua cópia ele se chama `speed2.exe`, o launcher o copia para `speed.exe` na primeira vez.
* As pastas do jogo: `Global`, `Cars`, `Tracks`, `FrontEnd`, `Sound`, `SNDSTREAMS`, `SpeechStreams`,
  `Languages`, `Movies`, `fx`.

## Instalação

```text
roms/ports/
├── NFSU1.sh                 launcher
└── nfsu1/
    ├── nfsu1.aarch64        o jogo (gerado por ports/r36s/build_nfsu1.sh)
    ├── nfsu1.cfg            configurações
    ├── port.json            dados do PortMaster
    ├── music/
    │   ├── menu/            suas músicas para os menus (.ogg / .mp3)
    │   └── race/            suas músicas para as corridas
    └── gamedata/            OS ARQUIVOS DO SEU JOGO DE PC (SPEED.EXE, Global/, Cars/, Tracks/ …)
        └── NFS Underground/ saves (criada pelo jogo)
```

Sobras do instalador (`setup/`, `AutoRun/`, `3DSetup/`, `SECDRV.SYS`, `DrvMgt.dll`, `nfscres.*` …) não são
usadas e podem ser apagadas. Abra o jogo em **Ports** no EmulationStation.

## Controles

Os nomes são os impressos nos botões do R36S. O controle envia as teclas de PC do jogo; a direção é analógica
pelo analógico esquerdo.

| Botão | Corrida | Menus |
|---|---|---|
| Analógico esquerdo | Direção (analógica) | Navegar |
| Direcional | Teclas Enter / 1 / M / Tab | Navegar |
| **B** (embaixo) | Acelerar | Confirmar (Enter) |
| **Y** (esquerda) | Frear / ré | Espaço |
| **A** (direita) | Freio de mão | Voltar (Esc) |
| **X** (em cima) | Câmera | Voltar (Esc) |
| **R1** | Nitro | — |
| **L1** | Olhar para trás | — |
| **R2 / L2** | Subir / descer marcha | — |
| **Start** | Pausa | Confirmar (Enter) |
| **Select** | Backspace | Backspace (Abandonar; apaga uma letra ao digitar) |
| **R3** | Teclado na tela | Teclado na tela (nome do perfil) |
| **Select + R1** | Próxima música | Próxima música |
| **Select + R3** | Liga/desliga o contador de FPS | Liga/desliga o contador de FPS |
| **Select + Start** | Sai para o menu do sistema | Sai para o menu do sistema |

O Select é enviado quando você solta o botão, e não é enviado quando fez parte de um combo.

## Música

O port toca as suas músicas, porque o player de streams do jogo ainda não funciona aqui (e muitas cópias do
NFSU1 vêm sem as faixas do EA Trax). Coloque arquivos `.ogg` ou `.mp3` (qualquer taxa, mono ou estéreo) em:

* `nfsu1/music/menu/` — tocam nos menus;
* `nfsu1/music/race/` — tocam nas corridas.

A lista troca alguns segundos depois que a corrida começa ou termina (o menu de pausa não troca), com uma
entrada suave, e cada lista continua de onde parou. Se uma pasta estiver vazia, a outra lista é usada.
**Select + R1** pula para a próxima música.

## Configurações (`nfsu1/nfsu1.cfg`)

| Configuração | Efeito |
|---|---|
| `NFSU1_FPS=30` | Limite de quadros: 30 ou 60 |
| `NFSU1_LANG=English` | English, Spanish, French, German, Italian, Dutch, Swedish |
| `NFSU1_MUSIC_VOLUME=70` | Volume da música de 0 a 100; 0 desliga o player |
| `NFSU1_MUSIC_SHUFFLE=1` | 1 ordem aleatória, 0 pela ordem dos nomes |
| `NFSU2_SHOW_FPS=1` | Contador de FPS desde o início |

As opções gráficas ficam no menu Opções do próprio jogo (são gravadas no perfil).

## Problemas

`nfsu1/log.txt` é o log da última execução, e `nfsu1/launcher.log` o do launcher. O player de música escreve
linhas `[NFSU1 MUSIC]` (faixas abertas e, a cada 10 s, quanto tocou); mensagens da biblioteca de áudio e arquivos
da EA usada pelo jogo aparecem como `[NFSU1 EA]`.

## Como compilar

Os arquivos de entrada do lifting do NFSU1 ficam em [`nfsu1/`](../../../nfsu1), na raiz do repositório (seeds,
`config/` e o `run_lift.py` que os lê); o script de build é [`ports/r36s/build_nfsu1.sh`](../build_nfsu1.sh).

1. pcrecomp: [sp00nznet/pcrecomp](https://github.com/sp00nznet/pcrecomp) no commit `35548b8`, com
   `patches/pcrecomp/*.patch` aplicados (`git am`).
2. Converta o `SPEED.EXE` (Python 3, ferramentas do pcrecomp):
   ```sh
   export PCRECOMP=/caminho/do/pcrecomp
   python3 nfsu1/scripts/run_lift.py catalog SPEED.EXE nfsu1/seeds.json catalog.json
   python3 nfsu1/scripts/run_lift.py lift SPEED.EXE catalog.json gen
   ```
3. Uma árvore de compilação: uma cópia do pcrecomp com patches em que `runtime/recomp32` e
   `runtime/win32hle` são trocados por `ports/r36s/sdk/include/recomp32` e `ports/r36s/sdk/include/win32hle`.
4. Compile num contêiner Ubuntu 22.04 com `g++-aarch64-linux-gnu` e `python3`:
   ```sh
   ROOT=$PWD PCRECOMP=/caminho/da/arvore GEN=/caminho/do/gen OUT=/caminho/de/saida \
     bash ports/r36s/build_nfsu1.sh
   ```
   O resultado é `out/nfsu1.aarch64` (e `nfsu1.aarch64.debug`, com símbolos). Um build completo leva alguns
   minutos numa máquina x86_64 com muitos núcleos; o código convertido tem cerca de 22 mil funções.

O player de música usa [stb_vorbis](https://github.com/nothings/stb) 1.22 e
[dr_mp3](https://github.com/mackron/dr_libs) 0.7.3 (domínio público / MIT-0), em `ports/r36s/third_party/`.
