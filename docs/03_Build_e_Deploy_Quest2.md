# Build e Deploy no Meta Quest 2

> Como **buildar** a aplicação VR em Godot 4.6.3 e **instalá-la no Meta Quest 2**.
> Pressuposto: o Quest 2 já está com **conta de desenvolvedor Meta logada**.

---

## Parte A — Ferramentas necessárias (no PC)

| Ferramenta | Versão | Observação |
|---|---|---|
| **Godot 4.6.3** | Standard | Versão GDScript (não precisa .NET aqui) |
| **OpenJDK** | **17** | Obrigatório para o export Android |
| **Android SDK** | API 32+ | Via Android Studio **ou** command-line tools |
| **Build Tools / Platform Tools** | recentes | Inclui o **`adb`** (Android Debug Bridge) |
| **Plugin Godot OpenXR Vendors** | compatível com 4.6 | Loader Meta + opções de export VR |

> O `adb` é essencial para instalar e depurar no dispositivo. Após instalar o
> Platform Tools, garanta que `adb` esteja no PATH (teste: `adb version`).

---

## Parte B — Configurar o ambiente de export no Godot

### B.1 Apontar JDK e Android SDK

1. **Editor → Editor Settings → Export → Android**.
2. Preencher:
   - **Android SDK Path** — pasta do SDK (ex.: `C:\Users\<você>\AppData\Local\Android\Sdk`).
   - **Java SDK Path / JDK** — pasta do **JDK 17**.
3. Godot validará o caminho (ícone verde = OK).

### B.2 Instalar o Android Build Template

- **Project → Install Android Build Template…**
- Cria `res://android/build`. Necessário porque o plugin OpenXR Vendors customiza o
  manifesto/Gradle do build.

### B.3 Habilitar os plugins

- **Project → Project Settings → Plugins**: ative
  - **Godot OpenXR Vendors**
  - **Godot XR Tools** (se usado)

### B.4 Keystore de debug

- Em **Editor Settings → Export → Android**, defina o **Debug Keystore**
  (Godot pode gerar um padrão automaticamente). Necessário para assinar o `.apk` de debug.

---

## Parte C — Criar o Export Preset Android (VR)

1. **Project → Export… → Add… → Android**.
2. No preset Android, ajuste:
   - **Runnable** = ✔ (permite *one-click deploy*).
   - **XR Features → XR Mode = `OpenXR`**.
   - **Vendor = Meta** (aparece graças ao plugin OpenXR Vendors).
   - Habilitar recursos conforme necessidade: **Hand Tracking**, **Passthrough**
     (para a primeira cena, deixar só o essencial).
3. **Architectures**: marcar **`arm64-v8a`** (o Quest 2 é ARM64). Desmarcar as demais.
4. **Permissões** — para ler o **vídeo externo** do armazenamento:
   - Marcar **`READ_EXTERNAL_STORAGE`** (e, dependendo da versão alvo,
     **`READ_MEDIA_VIDEO`**).
   - Em Android recente pode ser necessário **`MANAGE_EXTERNAL_STORAGE`** para acesso
     amplo a `/sdcard`. Para a entrega, preferir ler de uma pasta de mídia específica.
5. **Package / Unique Name** — defina um identificador, ex.: `com.unisinos.gafcinema`.
6. Confirme **Rendering Method = Mobile** (override `.mobile`) no projeto (ver Plano de Ação).

> Se o preset acusar erros (ícone vermelho), eles aparecem na parte inferior da janela
> de export — geralmente faltando SDK, JDK, build template ou keystore.

---

## Parte D — Preparar o Quest 2 para receber o app

> A conta de desenvolvedor já está logada. Falta habilitar o modo desenvolvedor e o USB.

1. **Ativar Modo Desenvolvedor** (uma vez):
   - No app **Meta Quest** (celular) → **Dispositivos** → selecione o Quest →
     **Modo de Desenvolvedor → Ativar**.
   - (Requer ter uma *organização de desenvolvedor* criada no painel da Meta — já
     atendido pela conta de desenvolvedor logada.)
2. **Conectar via USB-C** ao PC.
3. **Autorizar a depuração USB**: ao conectar, o Quest mostra um prompt
   **"Permitir depuração USB?"** dentro do headset → **Permitir** (marcar "sempre permitir").
4. Validar a conexão no PC:
   ```powershell
   adb devices
   ```
   Deve listar o dispositivo como `device` (se aparecer `unauthorized`, refaça o passo 3).

---

## Parte E — Instalar o app no Quest 2

Há três caminhos. O **E.1 (one-click)** é o mais simples para desenvolvimento.

### E.1 — One-click deploy pelo Godot (recomendado)

1. Com o Quest conectado e autorizado (`adb devices` OK).
2. No canto superior direito do editor Godot, aparece o ícone do **dispositivo Android**
   (ou use o botão **"Remote Deploy"**).
3. Clique para **buildar + instalar + rodar** automaticamente no headset.

### E.2 — Exportar `.apk` e instalar via `adb`

1. **Project → Export… → selecionar o preset Android → Export Project…**
   - Salvar como, ex.: `build/gafcinema.apk`.
   - Manter **"Export With Debug"** marcado para builds de teste.
2. Instalar no Quest:
   ```powershell
   adb install -r build/gafcinema.apk
   ```
   (`-r` reinstala por cima de uma versão anterior.)

### E.3 — Meta Quest Developer Hub (MQDH) (opcional)

- App da Meta para gerenciar o dispositivo: arrastar `.apk` para instalar, ver logs,
  capturar tela/vídeo, gerenciar arquivos. Útil, mas não obrigatório.

### Onde encontrar o app no Quest

- Apps instalados por fora da loja ficam em **Biblioteca → Fontes Desconhecidas**
  (*Unknown Sources*). Selecione `GAFCinema` para abrir.

---

## Parte F — Enviar o vídeo externo para o Quest

Como a tela lê o vídeo **de fora do app**, é preciso copiar um `.ogv` para o dispositivo.

1. Converter o vídeo para Theora (no PC):
   ```powershell
   ffmpeg -i entrada.mp4 -q:v 7 -q:a 5 filme.ogv
   ```
2. Criar a pasta e enviar via `adb`:
   ```powershell
   adb shell mkdir -p /sdcard/Movies/cinema
   adb push filme.ogv /sdcard/Movies/cinema/filme.ogv
   ```
3. Garantir que o caminho bate com o `caminho_externo` do `screen_player.gd`
   (`/sdcard/Movies/cinema/filme.ogv`).
4. Conceder permissão de armazenamento ao app, se solicitada (ou em
   **Configurações → Apps → GAFCinema → Permissões**).

---

## Parte G — Depuração e logs

- **Ver logs do app em tempo real:**
  ```powershell
  adb logcat -s godot
  ```
- **Listar dispositivos / reconectar:**
  ```powershell
  adb devices
  adb kill-server ; adb start-server
  ```
- **Desinstalar:**
  ```powershell
  adb uninstall com.unisinos.gafcinema
  ```

---

## Parte H — Iteração recomendada

1. **Desenvolver e validar em PCVR** (Quest Link) — ciclo de segundos.
2. Só **buildar `.apk`** quando a feature estiver estável — ciclo de minutos.
3. Usar **one-click deploy** (E.1) para reduzir atrito.
4. Acompanhar **performance no dispositivo** (alvo **72 Hz**); o que roda liso em PCVR
   pode pesar no Quest 2.

---

## Troubleshooting rápido

| Sintoma | Causa provável | Ação |
|---|---|---|
| Export acusa erro vermelho | Falta SDK/JDK/template/keystore | Revisar Partes B e C |
| `adb devices` mostra `unauthorized` | Prompt USB não autorizado | Reautorizar dentro do headset |
| App instala mas tela preta / 2D | OpenXR/Mobile não configurado | Revisar XR Enabled + renderer Mobile |
| App não roda como VR | Falta plugin OpenXR Vendors / XR Mode | Ativar plugin e setar XR Mode no preset |
| Vídeo não aparece | Caminho/permissão/formato | Conferir `.ogv`, caminho `/sdcard/...`, permissão de storage |
| Crash no boot do Quest | Renderer Forward+ | Trocar para Mobile/Compatibility |
| Baixo FPS | Cena pesada para Adreno 650 | Baked lighting, menos draw calls, materiais simples |
```