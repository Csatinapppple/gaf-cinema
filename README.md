# Cinema Virtual (GAFCinema)

Um **cinema social em Realidade Virtual** feito em **Godot 4.6.3**: vários usuários se
reúnem na mesma sala de cinema e **assistem a um vídeo juntos**, escolhido pelo host
(inclusive vídeos do YouTube). Alvo principal: **Meta Quest 2** (VR standalone), com
suporte a execução em **desktop** (modo "flat") para desenvolvimento e testes.

> Trabalho da disciplina de Tópicos Especiais em Computação — Realidade Virtual,
> Aumentada e Mista (Unisinos).
> **Equipe:** Christian Aguiar Plentz, Cássio Ferreira Braga.

---

## ✨ Funcionalidades

- **Sala de cinema em VR** (6DoF) usando o asset *Game Ready Cinema Hall*.
- **Locomoção VR:** movimento suave + giro em incrementos (snap turn), com colisão de
  paredes/poltronas e **subida da arquibancada** (stair-stepping). Caminhar físico
  (roomscale) com a cápsula seguindo a cabeça.
- **Locomoção desktop (flat):** WASD + mouse, para testar sem headset.
- **Multiplayer LAN** (listen-server, ENet): um jogador hospeda, os outros entram pelo IP.
  Avatares (cabeça + mãos) sincronizados.
- **Vídeo escolhido pelo host:** o host baixa do YouTube (via `yt-dlp`), converte para
  Ogg Theora (via `ffmpeg`, em paralelo usando todos os núcleos) e **transmite o vídeo
  para os clientes**.
- **Streaming progressivo + início sincronizado:** os clientes começam a tocar com um
  pequeno buffer (sem esperar o arquivo inteiro) e **todos iniciam juntos, do zero**
  (modelo de cinema).

---

## 🎮 Controles

### VR (Meta Quest 2 / PCVR)
| Ação | Controle |
|---|---|
| Andar | **Analógico esquerdo** (relativo ao olhar) |
| Girar (snap turn) | **Analógico direito** (esquerda/direita) |
| Subir/descer a arquibancada | Andar em direção aos degraus (automático) |

> Os controles são exibidos como *placeholders* (caixas) por enquanto; mãos/modelos
> detalhados e a interação de pegar objetos são evoluções futuras.

### Desktop (modo flat, sem headset)
| Ação | Tecla/Mouse |
|---|---|
| Andar | **W A S D** |
| Olhar | **Segurar/clicar com o botão esquerdo** captura o mouse; mova para olhar |
| Liberar o mouse | **Esc** (necessário para clicar no lobby) |

### Lobby / Sessão (UI de tela — desktop)
- **Hospedar** — vira o servidor da sala.
- **Entrar** — conecta ao IP informado (padrão `127.0.0.1`).
- **Painel do host** (aparece após hospedar):
  - **Carregar do YouTube** — cola a URL e o host baixa/converte/transmite.
  - **Testar local (.ogv)** — usa um arquivo `.ogv` local para teste.

> Fluxo recomendado (cinema): **conecte os clientes primeiro**, depois o host carrega o
> vídeo — assim todos começam juntos. Quem entra depois do início toca a partir do começo.

---

## 🧱 Arquitetura (resumo)

- **Renderer:** Mobile (Vulkan) — compatível com Quest e desktop.
- **XR:** OpenXR (nativo do Godot). Em desktop sem headset, cai em modo flat.
- **Rede:** API multiplayer de alto nível do Godot (`ENetMultiplayerPeer`), LAN/IP direto.
- **Vídeo:** o `VideoStreamPlayer` nativo toca **Ogg Theora**; o host faz todo o
  processamento (download + conversão) e transmite o `.ogv` em chunks com controle de
  fluxo; o cliente reproduz progressivamente enquanto recebe.

Documentação detalhada em [`docs/`](docs/):
- [Arquitetura](docs/01_Arquitetura.md)
- [Plano de ação / montagem da cena](docs/02_Plano_de_Acao.md)
- [Build e deploy no Quest 2](docs/03_Build_e_Deploy_Quest2.md)

---

## ▶️ Como rodar (desenvolvimento)

1. Abra o projeto no **Godot 4.6.3** (versão Standard/GDScript).
2. Para reproduzir vídeo no host: na **1ª vez**, o `yt-dlp` e o `ffmpeg` são baixados
   automaticamente para `user://` (precisa de internet).
3. **Play (F5).** Sem headset, roda em modo flat (desktop).
4. **Multiplayer local:** *Debug → Run Multiple Instances → 2*, depois Hospedar numa
   janela e Entrar (`127.0.0.1`) na outra.
5. **VR (PCVR):** com o runtime OpenXR da Meta ativo e o Quest via Link, rode normalmente.

Para gerar os executáveis (desktop e Quest), veja [docs/03_Build_e_Deploy_Quest2.md](docs/03_Build_e_Deploy_Quest2.md).

---

## 🛠️ Tecnologias e dependências

- **[Godot Engine 4.6.3](https://godotengine.org/)** — engine (MIT).
- **OpenXR** — runtime de XR (nativo no Godot).
- **[Godot OpenXR Vendors](https://github.com/GodotVR/godot_openxr_vendors)** — loader
  da Meta para exportar ao Quest (necessário para o build standalone).
- **[godot-yt-dlp](https://github.com/Nolkaloid/godot-yt-dlp)** (por *Nolkaloid*) —
  integração do `yt-dlp` no Godot (incluído em [`addons/godot-yt-dlp/`](addons/godot-yt-dlp/)).
- **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** — download de vídeos (baixado em runtime).
- **[FFmpeg](https://ffmpeg.org/)** — conversão para Ogg Theora (baixado em runtime no Windows).
- **Jolt Physics** — engine de física (integrada ao Godot).

---

## 🙏 Créditos de assets

- **Sala de cinema:** *Game Ready Cinema Hall Asset* por **Oxygen3D** —
  https://oxygen3d.itch.io/game-ready-cinema-hall-asset
  (detalhes e licença em [`assets/cinema_hall/README.md`](assets/cinema_hall/README.md)).

Agradecimentos aos autores das ferramentas open source listadas acima, que tornam este
projeto possível.

---

## 📄 Licença

O código deste projeto segue a licença em [`LICENSE`](LICENSE). As dependências e assets
de terceiros mantêm suas respectivas licenças, conforme os links acima.
