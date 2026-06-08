# Plano de Ação — Montagem da Sala de Cinema em VR

> Passo a passo para configurar a compatibilidade VR e montar a **primeira cena**
> (sala de cinema com tela que reproduz vídeo externo).
> Pré-requisito: ler [01_Arquitetura.md](01_Arquitetura.md).

A ordem das etapas importa: **primeiro a compatibilidade VR**, depois a cena, por último o vídeo.

---

## Etapa 0 — Pré-requisitos de ambiente (uma vez)

- [ ] **Godot 4.6.3** (versão **Standard/GDScript** — não precisa do .NET para este projeto).
- [ ] **OpenJDK 17** instalado (necessário para export Android).
- [ ] **Android SDK** — pode ser instalado pelo **Android Studio** ou pelo command-line tools.
- [ ] **Quest 2** com **Modo Desenvolvedor** ativado e conta de desenvolvedor Meta logada.
- [ ] **Cabo USB-C** (ou Air Link) para deploy/teste.

> Os detalhes de SDK/JDK e configuração de export ficam no documento
> [03_Build_e_Deploy_Quest2.md](03_Build_e_Deploy_Quest2.md). Aqui focamos na cena.

---

## Etapa 1 — Configurar o projeto para VR (compatibilidade)

### 1.1 Ajustar o renderer

1. **Project → Project Settings → Rendering → Renderer**
2. Defina **Rendering Method = `Mobile`** (recomendado para Quest 2).
   - Alternativa: `Compatibility` (GLES3) — mais leve em alguns casos, porém com menos
     recursos visuais. Escolher **um** e manter consistência.
3. Confirme que o override **`rendering_method.mobile`** está como `mobile`
   (é o valor efetivamente usado no build Android).

> Por que não Forward+? Ele não roda no Quest 2 standalone. Veja a nota no documento de arquitetura.

### 1.2 Habilitar OpenXR

1. **Project Settings → marque "Advanced Settings"** (canto superior direito).
2. **XR → OpenXR → Enabled = `On`**.
3. **XR → Shaders → Enabled = `On`** (gera variantes de shader necessárias para XR;
   sem isso a imagem pode sair errada nos dois olhos).
4. Reinicie o editor se solicitado.

### 1.3 Instalar os plugins

Via **AssetLib** (aba no topo do editor) ou GitHub:

1. [ ] **Godot OpenXR Vendors** — habilita export para Quest (loader da Meta).
   - Após instalar: **Project → Project Settings → Plugins → ativar**.
2. [ ] **Godot XR Tools** — rig do jogador, mãos e interação.
   - Após instalar: ativar em **Plugins**.

### 1.4 Instalar o Android Build Template

- **Project → Install Android Build Template…** (cria a pasta `android/build`).
- Necessário porque o plugin OpenXR Vendors injeta configurações no `AndroidManifest`/Gradle.

### 1.5 Verificação rápida (smoke test PCVR)

Antes de modelar a cena, valide que o XR sobe:

- Conecte o Quest via **Quest Link** (ou Air Link) com o **runtime OpenXR da Meta** ativo no PC.
- Rode a cena de bootstrap (Etapa 2) e confirme que aparece a imagem nos dois olhos e
  o *head tracking* funciona. Iterar em PCVR é **muito** mais rápido que buildar `.apk`.

---

## Etapa 2 — Bootstrap do XR e rig do jogador

### 2.1 Cena principal e script de inicialização

Crie `scenes/main.tscn` com nó raiz `Node3D` (nome `Main`) e o script
`scripts/xr/xr_bootstrap.gd`:

```gdscript
extends Node3D

func _ready() -> void:
    var xr_interface := XRServer.find_interface("OpenXR")
    if xr_interface and xr_interface.is_initialized():
        print("OpenXR inicializado.")
        get_viewport().use_xr = true       # ativa renderização estereoscópica
    else:
        push_warning("OpenXR não inicializou — rodando em modo desktop.")
```

> Defina `main.tscn` como **cena principal** em Project Settings → Application → Run.

### 2.2 Adicionar o rig do jogador

- Instancie o rig do **Godot XR Tools** (`addons/godot-xr-tools/...`) dentro de `Main`,
  **ou** monte manualmente:
  - `XROrigin3D`
    - `XRCamera3D`
    - `XRController3D` (Left) — `tracker = "left_hand"`
    - `XRController3D` (Right) — `tracker = "right_hand"`
- Posicione o `XROrigin3D` no ponto onde o jogador deve "nascer" (uma poltrona central,
  por exemplo). A altura é dada pelo headset; o chão do play area = Y do origin.

---

## Etapa 3 — Montar a sala de cinema

> Pode-se começar com geometria primitiva (caixas/planos) e refinar com modelos depois.

### 3.1 Geometria base (`scenes/rooms/cinema_room.tscn`)

- [ ] **Chão** — `MeshInstance3D` (PlaneMesh) + `StaticBody3D` com `CollisionShape3D`.
- [ ] **Paredes e teto** — caixas (BoxMesh) formando a sala fechada.
- [ ] **Poltronas** — instâncias de um modelo de cadeira (ou caixas como placeholder),
      dispostas em fileiras voltadas para a tela.
- [ ] **Tela (parede frontal)** — base onde a imagem será projetada (Etapa 4).

### 3.2 Iluminação (otimizada para Quest)

- [ ] `WorldEnvironment` com `Environment`:
  - `Background = Color` (escuro, ambiente de cinema).
  - `Ambient light` baixa.
  - Evitar SSAO/SSR/glow pesados no renderer Mobile.
- [ ] Luzes pontuais discretas (corredor/saídas).
- [ ] **Preferir iluminação "baked"** (LightmapGI) sobre luz dinâmica para performance.
- [ ] Meta: manter a cena leve para sustentar **72 Hz**.

### 3.3 Escala e conforto VR

- Conferir a **escala real** (1 unidade = 1 metro). Uma poltrona ~0,5 m, pé-direito ~3 m.
- A tela deve estar a uma distância confortável (ex.: 6–10 m) e com tamanho condizente.
- Evitar movimento de câmera forçado (causa enjoo) — câmera segue só o headset.

---

## Etapa 4 — Tela de vídeo

### 4.1 Montar a hierarquia da tela

Dentro de `cinema_room.tscn`, no nó `Screen`:

```
Screen (Node3D)
├── ScreenMesh (MeshInstance3D — QuadMesh/PlaneMesh, proporção 16:9)
├── SubViewport
│   └── VideoStreamPlayer
└── AudioStreamPlayer3D        (opcional, áudio espacial)
```

Configurar o `SubViewport`:
- `size` = resolução do vídeo (ex.: 1280×720).
- `render_target_update_mode = Always`.

### 4.2 Material da tela

No `ScreenMesh`, criar um `StandardMaterial3D`:
- `albedo_texture` ou (melhor) `emission` → **`ViewportTexture`** apontando para o `SubViewport`.
- `emission_enabled = true`, `emission_energy` alto, para a tela "brilhar" no escuro.
- Opcional: `shading_mode = Unshaded` para imagem fiel independente da luz da sala.

### 4.3 Script de reprodução (`scripts/cinema/screen_player.gd`)

```gdscript
extends Node3D

@export var caminho_externo: String = "/sdcard/Movies/cinema/filme.ogv"
@export var fallback_embutido: String = "res://assets/videos/exemplo.ogv"

@onready var player: VideoStreamPlayer = $SubViewport/VideoStreamPlayer

func _ready() -> void:
    if not _tocar_externo(caminho_externo):
        _tocar_embutido(fallback_embutido)

func _tocar_externo(caminho: String) -> bool:
    if not FileAccess.file_exists(caminho):
        return false
    var stream := VideoStreamTheora.new()
    stream.file = caminho
    player.stream = stream
    player.play()
    return true

func _tocar_embutido(caminho: String) -> void:
    player.stream = load(caminho)
    player.play()
```

> **Formato:** o `VideoStreamPlayer` nativo reproduz **Ogg Theora (`.ogv`)**.
> Converter o vídeo de teste com FFmpeg:
> `ffmpeg -i entrada.mp4 -q:v 7 -q:a 5 saida.ogv`

### 4.4 Áudio do vídeo

- Por padrão o `VideoStreamPlayer` toca o áudio próprio (`bus`).
- Para áudio espacial vindo da tela, rotear via `AudioStreamPlayer3D` posicionado no `Screen`.

---

## Etapa 5 — Integração e teste em PCVR

- [ ] Instanciar `cinema_room.tscn` e o rig do jogador em `main.tscn`.
- [ ] Rodar via Quest Link e validar:
  - Imagem estéreo correta e *tracking* 6DoF.
  - Tela exibindo o vídeo (fallback embarcado).
  - Escala/conforto da sala.
- [ ] Ajustar performance (FPS, draw calls).

---

## Etapa 6 — Preparar para o Quest standalone

- [ ] Confirmar renderer **Mobile/Compatibility** e plugins ativos.
- [ ] Configurar export Android e permissões (armazenamento p/ vídeo externo).
- [ ] Buildar `.apk` e instalar — **detalhado em
      [03_Build_e_Deploy_Quest2.md](03_Build_e_Deploy_Quest2.md)**.
- [ ] Testar leitura do vídeo externo (`adb push` do `.ogv` para `/sdcard/Movies/cinema/`).

---

## Checklist resumido

| # | Etapa | Concluído |
|---|---|---|
| 0 | Ambiente (Godot, JDK, SDK, Quest dev mode) | ☐ |
| 1 | Renderer Mobile + OpenXR + plugins + build template | ☐ |
| 2 | Bootstrap XR + rig do jogador | ☐ |
| 3 | Geometria + iluminação da sala | ☐ |
| 4 | Tela + vídeo (SubViewport + VideoStreamPlayer) | ☐ |
| 5 | Teste integrado em PCVR | ☐ |
| 6 | Build e deploy no Quest 2 | ☐ |
```