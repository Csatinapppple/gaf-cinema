# Arquitetura do Projeto — Cinema Virtual (VR / Meta Quest 2)

> Documento guia de arquitetura para o início do desenvolvimento.
> Engine: **Godot 4.6.3** · Alvo: **Meta Quest 2 (standalone Android)** · Tipo: **VR 6DoF**

---

## 1. Visão técnica geral

O objetivo desta primeira entrega é a **primeira cena do jogo**: uma sala de cinema em VR
contendo uma **tela** capaz de reproduzir **vídeos vindos de fora da aplicação** (do
armazenamento do dispositivo), com o usuário imerso em 6DoF.

O projeto roda em duas situações que precisam conviver:

| Cenário | Uso | Renderer | Transporte XR |
|---|---|---|---|
| **PCVR (desenvolvimento)** | Iteração rápida no editor | Mobile ou Forward+ | Quest Link / Air Link (OpenXR no PC) |
| **Standalone (entrega)** | Build `.apk` rodando no próprio Quest 2 | **Mobile (Vulkan)** ou Compatibility | OpenXR + Meta loader (no dispositivo) |

> ⚠️ **Decisão arquitetural crítica:** o projeto está hoje configurado como
> **Forward+** com driver **d3d12** (ver `project.godot`). O renderer Forward+ **não
> executa no Quest 2 standalone**. Para o build Android usaremos o renderer **Mobile**
> (Vulkan) — ou, alternativamente, **Compatibility** (OpenGL ES 3). Isso é tratado no
> documento [02_Plano_de_Acao.md](02_Plano_de_Acao.md).

---

## 2. Stack de tecnologias

- **Godot 4.6.3** — engine.
- **OpenXR** — runtime de XR, **nativo no Godot 4** (não precisa de plugin para o core).
- **Godot OpenXR Vendors** (`godotengine/godot-openxr-vendors`) — plugin **obrigatório
  para exportar ao Quest**: fornece o *loader* OpenXR da Meta e as opções de export
  Android específicas (hand tracking, passthrough, etc.).
- **Godot XR Tools** (`GodotVR/godot-xr-tools`) — addon que provê *rig* do jogador,
  locomoção, mãos, e sistema de *interactables* (segurar/arremessar objetos). Acelera
  bastante as mecânicas descritas no XRDD (pegar pipoca, etc.).
- **Jolt Physics** — engine de física (já habilitada no projeto). Compatível com as
  mãos baseadas em física previstas no XRDD.
- **Reprodução de vídeo:**
  - **Nativo:** Godot reproduz **Ogg Theora (`.ogv`)** via `VideoStreamPlayer` —
    sem dependências externas. **É o caminho recomendado para esta primeira cena.**
  - **MP4/H.264 (extensão futura):** Godot **não** decodifica MP4 nativamente.
    Para suportar vídeos arbitrários do usuário, será necessário um plugin
    (ex.: *GoZen* ou um wrapper FFmpeg). Fica como evolução — ver seção 6.

---

## 3. Estrutura de pastas proposta

```
res://
├── project.godot
├── scenes/
│   ├── main.tscn                 # cena de entrada — bootstrap XR
│   ├── rooms/
│   │   └── cinema_room.tscn      # a sala de cinema (geometria, luzes, tela)
│   └── player/
│       └── xr_player.tscn        # rig do jogador (origin + câmera + controllers + mãos)
├── scripts/
│   ├── xr/
│   │   └── xr_bootstrap.gd        # inicializa a interface OpenXR
│   └── cinema/
│       └── screen_player.gd       # controla a reprodução de vídeo na tela
├── assets/
│   ├── models/                    # cadeiras, paredes, props
│   ├── materials/
│   ├── textures/
│   ├── audio/
│   └── videos/                    # vídeo(s) .ogv de exemplo embarcado(s)
├── addons/
│   ├── godot-xr-tools/            # addon (via AssetLib)
│   └── godotopenxrvendors/        # plugin de export Quest (via AssetLib)
└── docs/
    ├── 01_Arquitetura.md
    ├── 02_Plano_de_Acao.md
    └── 03_Build_e_Deploy_Quest2.md
```

---

## 4. Arquitetura de cenas (runtime)

### 4.1 Árvore de nós da cena principal

```
Main (Node3D)                         ← scenes/main.tscn  (script: xr_bootstrap.gd)
├── XROrigin3D                        ← espaço de referência do jogador (chão = play area)
│   ├── XRCamera3D                    ← cabeça/HMD (segue o headset)
│   ├── LeftController  (XRController3D)
│   │   └── (mão / mesh / ray de UI)
│   └── RightController (XRController3D)
│       └── (mão / mesh / ray de UI)
├── CinemaRoom (instância de cinema_room.tscn)
│   ├── Environment / WorldEnvironment
│   ├── Floor / Walls / Ceiling (MeshInstance3D + StaticBody3D)
│   ├── Seats (cadeiras)
│   ├── Lights
│   └── Screen                       ← a tela do cinema
│       ├── ScreenMesh (MeshInstance3D — quad/plano)
│       ├── SubViewport
│       │   └── VideoStreamPlayer    ← decodifica o vídeo
│       └── AudioStreamPlayer3D      ← (opcional) áudio espacializado
└── (futuro) NetworkManager, AvatarSpawner, UIPanel...
```

> Usando **Godot XR Tools**, o `xr_player.tscn` já traz `XROrigin3D` + `XRCamera3D` +
> controllers com mãos e *function pickup/movement* prontos; basta instanciá-lo dentro de `Main`.

### 4.2 Como a tela recebe o vídeo (pipeline de render)

O padrão recomendado para exibir vídeo numa superfície 3D:

1. Um **`VideoStreamPlayer`** é colocado dentro de um **`SubViewport`**.
2. O `SubViewport` gera uma **`ViewportTexture`**.
3. Essa textura é atribuída ao **`albedo`** (emissive, idealmente) de um
   `StandardMaterial3D` aplicado ao **`ScreenMesh`** (um *quad*).
4. Resultado: o vídeo aparece "projetado" na tela.

> Alternativa mais simples (sem SubViewport): pegar `VideoStreamPlayer.get_video_texture()`
> e aplicá-la diretamente ao material. O SubViewport é preferível porque facilita
> compor UI/overlays sobre o vídeo e controlar resolução.

Para a tela ser **bem visível em VR**, o material deve usar `emission` (a tela
"emite luz própria"), com `shading_mode = unshaded` ou emissão forte, evitando que a
iluminação ambiente apague a imagem.

### 4.3 Origem do vídeo ("de fora da aplicação")

O requisito de "receber vídeos de fora da aplicação" é atendido carregando o stream em
**tempo de execução** a partir do armazenamento do dispositivo (e não como recurso
embarcado no `.apk`):

```gdscript
# screen_player.gd (exemplo conceitual)
var stream := VideoStreamTheora.new()
stream.file = caminho_externo            # ex.: "/sdcard/Movies/cinema/filme.ogv"
$SubViewport/VideoStreamPlayer.stream = stream
$SubViewport/VideoStreamPlayer.play()
```

No Quest 2 (Android), o app precisa de permissão de leitura de armazenamento e o vídeo
deve estar numa pasta acessível (ex.: `/sdcard/Movies/...`, copiada via `adb push` ou MQDH).
Detalhes de permissões e *deploy* do arquivo de vídeo estão em
[03_Build_e_Deploy_Quest2.md](03_Build_e_Deploy_Quest2.md).

Para esta primeira cena, recomenda-se ter **um `.ogv` de exemplo embarcado** em
`assets/videos/` como *fallback*, e a leitura externa como caminho principal.

---

## 5. Configurações de projeto essenciais para VR

Resumo (passo a passo detalhado no Plano de Ação):

- **Project Settings → XR → OpenXR → Enabled = `true`**
- **Project Settings → XR → Shaders → Enabled = `true`** (compila variantes de shader para XR)
- **Rendering → Renderer → Rendering Method = `mobile`** (para paridade com o Quest;
  o override `.mobile` é o que vale no build Android)
- **Remover/ajustar** `rendering_device/driver.windows="d3d12"` se causar conflito com
  Vulkan/OpenXR no PC — em geral OpenXR no Windows funciona melhor com Vulkan.
- **Android build template** instalado (Project → Install Android Build Template).
- **Plugin OpenXR Vendors** habilitado, com export preset Android configurado para a Meta.

---

## 6. Roadmap de evolução (após a primeira cena)

Em ordem sugerida, alinhado ao XRDD:

1. **Interação física** com props (pipoca/refrigerante) via XR Tools *pickup*.
2. **Locomoção** (teletransporte + movimento suave por controle).
3. **UI flutuante** (painel de menu / playlist) com `XRTools Pointer`.
4. **Multiplayer** (avatares assistindo juntos) — `MultiplayerSynchronizer` / `ENet` ou
   serviço dedicado. É a feature mais cara; planejar separadamente.
5. **Vídeo arbitrário (MP4)** via plugin de decodificação + upload pelo usuário.
6. **Playlist e votação** para pular vídeo.

---

## 7. Riscos e pontos de atenção

- **Renderer:** Forward+ não roda no Quest. Validar cedo o build Mobile/Compatibility.
- **Performance:** o Quest 2 é hardware móvel (Adreno 650). Orçar *draw calls*,
  polígonos e luzes; preferir *baked lighting* e materiais simples. Meta de **72 Hz**.
- **Formato de vídeo:** limitação nativa ao Theora. Converter vídeos de teste para `.ogv`.
- **Permissões Android:** acesso a armazenamento para ler o vídeo externo.
- **Plugin de export:** sem o OpenXR Vendors, o `.apk` não roda como app VR no Quest.
```