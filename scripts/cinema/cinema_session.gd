extends Node
## Sessão de cinema em rede.
##
## O HOST escolhe o vídeo (YouTube via yt-dlp, ou arquivo local de teste), faz TODO
## o processamento (download + conversão para .ogv com ffmpeg), reproduz na própria
## tela e TRANSMITE o arquivo .ogv para cada cliente — inclusive para quem conecta
## depois. Os clientes salvam o arquivo recebido e reproduzem em sincronia.
##
## Toda a parte pesada (yt-dlp/ffmpeg) roda só no host; os clientes apenas recebem
## bytes e tocam, então funcionam até no Quest.

const PASTA := "user://cinema/"
const ARQUIVO_OGV := "user://cinema/atual.ogv"     # host (convertido)
const ARQUIVO_RECV := "user://cinema/recebido.ogv" # cliente (recebido pela rede)
const NOME_MP4 := "baixado"
const CHUNK := 65536          # 64 KB por pacote
const CHUNKS_POR_FRAME := 24  # teto de pacotes por frame
const WINDOW := 1048576       # 1 MB em trânsito (controle de fluxo p/ não inchar o ENet)
const ACK_INTERVALO := 262144 # cliente confirma a cada ~256 KB
const INTERVALO_SYNC := 0.5   # segundos entre sincronizações de tempo (cinema: apertado)
const BUFFER_INICIAL := 2097152  # 2 MB: cliente começa a tocar após esse buffer (streaming progressivo)

## Caminho do nó da tela (screen_player.gd).
@export var caminho_tela: NodePath

signal estado_mudou(texto: String)

@onready var _tela: Node = get_node(caminho_tela)

# --- Host ---
var _bytes: PackedByteArray = PackedByteArray()  # vídeo atual em memória
var _envios: Dictionary = {}                     # peer_id -> {off, ack}
var _ocupado: bool = false                       # evita downloads simultâneos
var _pids_ativos: Array[int] = []                # PIDs de ffmpeg/yt-dlp p/ matar ao sair
# Coordenação de início simultâneo (cinema: todos começam juntos, do zero).
var _video_armado: bool = false                  # vídeo preparado, aguardando início
var _reproducao_iniciada: bool = false
var _prontos: Dictionary = {}                    # peer_id -> true (cliente bufferizou)
# --- Cliente ---
var _recv_file: FileAccess = null
var _recv_total: int = 0
var _recv_recebido: int = 0
var _desde_ack: int = 0
var _recv_pct: int = 0
var _recv_preparado: bool = false  # já preparou o vídeo e avisou "pronto"?


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA))
	multiplayer.peer_connected.connect(_ao_peer_conectar)


func _exit_tree() -> void:
	# create_process não morre junto com o app — mata os filhos pendentes para não
	# deixar ffmpeg/yt-dlp órfãos rodando.
	for pid in _pids_ativos:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids_ativos.clear()


## Lança um processo externo rastreando o PID (para poder matá-lo ao sair).
func _spawn(exe: String, args: PackedStringArray) -> int:
	var pid := OS.create_process(exe, args)
	if pid > 0:
		_pids_ativos.append(pid)
	return pid


# ============================ HOST: escolher vídeo ============================

## Baixa um vídeo do YouTube (até 720p), converte para .ogv e publica.
func host_carregar_youtube(url: String) -> void:
	if not multiplayer.is_server():
		return
	if _ocupado or url.strip_edges().is_empty():
		return
	_ocupado = true

	if not YtDlp.is_setup():
		_estado("Preparando yt-dlp/ffmpeg (primeira vez baixa binários)...")
		YtDlp.setup()
		await YtDlp.setup_completed

	# Remove qualquer saída antiga para garantir que NUNCA reaproveitamos um vídeo
	# de uma execução anterior (só o vídeo desta URL será usado).
	_limpar_saidas()

	var mp4 := ProjectSettings.globalize_path(PASTA) + NOME_MP4 + ".mp4"
	_estado("Baixando do YouTube (até 720p)...")
	if not await _baixar_youtube(url, mp4):
		_estado("Falha no download.")
		_ocupado = false
		return
	# Loga o que foi baixado (confirme que bate com o seu vídeo).
	var dur := _duracao_segundos(mp4)
	_estado("Baixado: %d KB, %ds de vídeo." % [_tamanho_kb(mp4), int(dur)])

	_estado("Convertendo para .ogv...")
	if not await _converter_para_ogv(mp4, ProjectSettings.globalize_path(ARQUIVO_OGV)):
		_estado("Falha na conversão (ffmpeg).")
		_ocupado = false
		return

	_publicar_video(ARQUIVO_OGV)
	_ocupado = false


## Remove vídeo baixado, convertido e segmentos de execuções anteriores.
func _limpar_saidas() -> void:
	var pasta := ProjectSettings.globalize_path(PASTA)
	var nomes := ["%s.mp4" % NOME_MP4, "atual.ogv", "segmentos.txt"]
	for nome in nomes:
		if FileAccess.file_exists(pasta + nome):
			DirAccess.remove_absolute(pasta + nome)
	# Segmentos seg_*.ogv
	var d := DirAccess.open(pasta)
	if d != null:
		for arq in d.get_files():
			if arq.begins_with("seg_") and arq.ends_with(".ogv"):
				DirAccess.remove_absolute(pasta + arq)


## Baixa com o yt-dlp instalado pelo addon, limitando a 720p e preferindo H.264 (avc1).
## 4K/AV1 é enorme e lentíssimo de decodificar → a conversão demoraria minutos.
func _baixar_youtube(url: String, saida_mp4: String) -> bool:
	var ehwin := OS.get_name() == "Windows"
	var ytdlp := ProjectSettings.globalize_path("user://yt-dlp.exe" if ehwin else "user://yt-dlp")
	var ffmpeg_loc := ProjectSettings.globalize_path("user://ffmpeg.exe") if ehwin else "ffmpeg"
	if FileAccess.file_exists(saida_mp4):
		DirAccess.remove_absolute(saida_mp4)
	# --no-progress evita inundar o stderr (que é herdado pelos filhos e pode travá-los).
	var args := PackedStringArray([
		"--no-playlist", "--no-progress", "--no-warnings",
		"-f", "bestvideo[height<=720][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=720]/best",
		"--merge-output-format", "mp4",
		"--ffmpeg-location", ffmpeg_loc,
		"-o", saida_mp4,
		url,
	])
	return await _rodar_processo(ytdlp, args, "Baixando", saida_mp4)


## Publica um .ogv já existente (teste local, sem YouTube). Aceita res:// ou user://.
func host_carregar_arquivo(caminho_ogv: String) -> void:
	if not multiplayer.is_server() or _ocupado:
		return
	_publicar_video(caminho_ogv)


## Converte um vídeo para Ogg Theora.
##
## O encoder libtheora é SINGLE-THREAD (não existe flag que o torne multi-core), então
## para usar todos os núcleos dividimos o vídeo em N segmentos convertidos em paralelo
## (um ffmpeg por segmento) e depois concatenamos sem recodificar (-c copy).
## N é derivado de OS.get_processor_count() — nunca hardcoded.
func _converter_para_ogv(entrada: String, saida: String) -> bool:
	var ffmpeg := _ffmpeg_path()
	var dur := _duracao_segundos(entrada)

	# Nº de segmentos = núcleos disponíveis, com teto e mínimo de ~4s por segmento.
	var n := clampi(OS.get_processor_count(), 1, 16)
	if dur > 0.0:
		n = clampi(n, 1, maxi(1, int(dur / 4.0)))

	# Sem duração confiável ou só 1 núcleo: conversão única (caminho simples).
	if dur <= 0.0 or n <= 1:
		return await _rodar_processo(ffmpeg, _args_ffmpeg_unico(entrada, saida), "Convertendo", saida)

	var seg := ceilf(dur / float(n))
	var pasta := ProjectSettings.globalize_path(PASTA)
	var segmentos: Array[String] = []
	var pids: Array[int] = []
	for i in n:
		var sp := pasta + "seg_%d.ogv" % i
		segmentos.append(sp)
		# -loglevel error -nostats: sem isso, N ffmpeg inundam o stderr herdado do app
		# (canalizado p/ o editor) e travam ao encher o pipe.
		var args := PackedStringArray([
			"-hide_banner", "-loglevel", "error", "-nostats", "-nostdin", "-y",
			"-ss", str(float(i) * seg), "-t", str(seg),
			"-i", entrada,
			"-vf", "scale='min(1280,iw)':-2", "-r", "30",
			"-c:v", "libtheora", "-q:v", "5",
			"-c:a", "libvorbis", "-q:a", "3",
			sp,
		])
		var pid := _spawn(ffmpeg, args)
		if pid > 0:
			pids.append(pid)
	if pids.is_empty():
		return false

	var t := 0.0
	while _algum_processo_rodando(pids):
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		_estado("Convertendo em paralelo (%d núcleos)... %ds" % [n, int(t)])
	for pid in pids:
		_pids_ativos.erase(pid)

	return await _concatenar(segmentos, saida)


## Concatena os segmentos .ogv sem recodificar e remove os temporários.
func _concatenar(segmentos: Array[String], saida: String) -> bool:
	var lista := ProjectSettings.globalize_path(PASTA) + "segmentos.txt"
	var f := FileAccess.open(lista, FileAccess.WRITE)
	if f == null:
		return false
	for s in segmentos:
		# Nome relativo (mesma pasta do .txt) — o concat resolve a partir do .txt.
		f.store_line("file '%s'" % s.get_file())
	f.close()

	var args := PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-nostats", "-nostdin", "-y",
		"-f", "concat", "-safe", "0", "-i", lista,
		"-c", "copy", saida,
	])
	var ok := await _rodar_processo(_ffmpeg_path(), args, "Finalizando", saida)

	for s in segmentos:
		DirAccess.remove_absolute(s)
	DirAccess.remove_absolute(lista)
	return ok


## Duração do vídeo em segundos via ffprobe (0.0 se indisponível).
func _duracao_segundos(arquivo: String) -> float:
	var saida_arr := []
	var code := OS.execute(_ffprobe_path(), PackedStringArray([
		"-v", "error", "-show_entries", "format=duration",
		"-of", "default=noprint_wrappers=1:nokey=1", arquivo,
	]), saida_arr, true)
	if code != 0 or saida_arr.is_empty():
		return 0.0
	return float(String(saida_arr[0]).strip_edges())


func _args_ffmpeg_unico(entrada: String, saida: String) -> PackedStringArray:
	return PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-nostats", "-nostdin", "-y", "-i", entrada,
		"-vf", "scale='min(1280,iw)':-2", "-r", "30",
		"-c:v", "libtheora", "-q:v", "5",
		"-c:a", "libvorbis", "-q:a", "3",
		saida,
	])


func _algum_processo_rodando(pids: Array[int]) -> bool:
	for pid in pids:
		if OS.is_process_running(pid):
			return true
	return false


func _ffmpeg_path() -> String:
	if OS.get_name() == "Windows":
		return ProjectSettings.globalize_path("user://ffmpeg.exe")
	return "ffmpeg"


func _ffprobe_path() -> String:
	if OS.get_name() == "Windows":
		return ProjectSettings.globalize_path("user://ffprobe.exe")
	return "ffprobe"


## Executa um processo externo sem bloquear a engine (poll do PID), reportando
## progresso (tempo + tamanho do arquivo de saída). Retorna true se gerou saída.
func _rodar_processo(exe: String, args: PackedStringArray, rotulo: String, arquivo: String) -> bool:
	var pid := _spawn(exe, args)
	if pid <= 0:
		_estado("Falha ao iniciar %s" % exe.get_file())
		return false
	var t := 0.0
	var prox := 2.0
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		if t >= prox:
			prox += 2.0
			_estado("%s... %ds (%d KB)" % [rotulo, int(t), _tamanho_kb(arquivo)])
	_pids_ativos.erase(pid)
	return _tamanho_kb(arquivo) > 0


func _tamanho_kb(caminho: String) -> int:
	if not FileAccess.file_exists(caminho):
		return 0
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		return 0
	var tam := f.get_length()
	f.close()
	return tam / 1024


## Carrega os bytes do .ogv, PREPARA a tela do host (sem tocar) e dispara a transmissão.
## A reprodução só começa quando todos os clientes estiverem prontos (início simultâneo).
func _publicar_video(caminho_ogv: String) -> void:
	var f := FileAccess.open(caminho_ogv, FileAccess.READ)
	if f == null:
		_estado("Não foi possível abrir o vídeo: %s" % caminho_ogv)
		return
	_bytes = f.get_buffer(f.get_length())
	f.close()
	if _bytes.is_empty():
		_estado("Vídeo vazio.")
		return

	_tela.preparar(caminho_ogv)        # host pronto no frame 0, ainda pausado
	_video_armado = true
	_reproducao_iniciada = false
	_prontos.clear()
	_estado("Vídeo pronto (%d KB). Transmitindo a %d cliente(s)..."
		% [_bytes.size() / 1024, multiplayer.get_peers().size()])
	for peer in multiplayer.get_peers():
		_iniciar_envio(peer)

	_verificar_inicio()  # se não há clientes, começa já
	# Timeout de segurança: se algum cliente não ficar "pronto", começa mesmo assim.
	await get_tree().create_timer(10.0).timeout
	if not _reproducao_iniciada:
		_disparar_inicio()


func _iniciar_envio(peer: int) -> void:
	if _bytes.is_empty():
		return
	_envios[peer] = {"off": 0, "ack": 0, "pct": 0}
	rpc_id(peer, "iniciar_transferencia", _bytes.size())
	print("[Cinema] Início de envio ao cliente %d (%d KB)." % [peer, _bytes.size() / 1024])


# ============================ HOST: loop de envio/sync ============================

func _process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	_enviar_chunks_pendentes()


func _enviar_chunks_pendentes() -> void:
	for peer in _envios.keys():
		var e: Dictionary = _envios[peer]
		var off: int = e["off"]
		var enviados := 0
		# Envia mantendo no máximo WINDOW bytes não confirmados em trânsito.
		while off < _bytes.size() and (off - int(e["ack"])) < WINDOW and enviados < CHUNKS_POR_FRAME:
			var fim := mini(off + CHUNK, _bytes.size())
			rpc_id(peer, "receber_chunk", _bytes.slice(off, fim))
			off = fim
			enviados += 1
		e["off"] = off
		# Progresso baseado no que o cliente confirmou (ack).
		var pct := int(int(e["ack"]) * 100 / maxi(_bytes.size(), 1))
		if pct >= int(e["pct"]) + 10:
			e["pct"] = pct
			_estado("Enviando ao cliente %d: %d%%" % [peer, pct])
		# Finaliza quando o cliente confirmou ter recebido tudo.
		if int(e["ack"]) >= _bytes.size():
			rpc_id(peer, "finalizar_transferencia")
			_envios.erase(peer)
			_estado("Envio ao cliente %d concluído." % peer)


## Chamado pelo CLIENTE para confirmar quantos bytes já recebeu (controle de fluxo).
@rpc("any_peer", "call_remote", "reliable")
func confirmar(recebido: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _envios.has(peer):
		_envios[peer]["ack"] = recebido


## Novo cliente entrou: se já há vídeo, transmite para ele.
func _ao_peer_conectar(peer: int) -> void:
	if multiplayer.is_server() and not _bytes.is_empty():
		_iniciar_envio(peer)


# ============================ CLIENTE: recepção ============================

@rpc("authority", "call_remote", "reliable")
func iniciar_transferencia(tamanho: int) -> void:
	if _recv_file != null:
		_recv_file.close()
	_recv_file = FileAccess.open(ARQUIVO_RECV, FileAccess.WRITE)
	if _recv_file == null:
		_estado("Falha ao criar arquivo de recepção.")
		return
	_recv_total = tamanho
	_recv_recebido = 0
	_desde_ack = 0
	_recv_pct = 0
	_recv_preparado = false
	_estado("Recebendo vídeo do host (%d KB)..." % (tamanho / 1024))


@rpc("authority", "call_remote", "reliable")
func receber_chunk(dados: PackedByteArray) -> void:
	# Pacotes reliable chegam em ordem; grava direto no arquivo e dá flush para o
	# VideoStreamPlayer (handle de leitura separado) enxergar os dados novos.
	if _recv_file == null:
		return
	_recv_file.store_buffer(dados)
	_recv_file.flush()
	_recv_recebido += dados.size()
	_desde_ack += dados.size()
	var pct := int(_recv_recebido * 100 / maxi(_recv_total, 1))
	if pct >= _recv_pct + 10:
		_recv_pct = pct
		_estado("Recebendo do host: %d%%" % pct)

	# Ao bufferizar o início, PREPARA o vídeo (sem tocar) e avisa o host que está
	# pronto. O host só dispara a reprodução quando todos estiverem prontos → início
	# simultâneo. (Streaming progressivo: o resto continua chegando enquanto toca.)
	if not _recv_preparado and _recv_recebido >= mini(_recv_total, BUFFER_INICIAL):
		_recv_preparado = true
		_tela.preparar(ARQUIVO_RECV)
		rpc_id(1, "cliente_pronto")
		_estado("Pronto — aguardando o host iniciar...")

	# Confirma periodicamente (controle de fluxo) e ao receber tudo.
	if _desde_ack >= ACK_INTERVALO or _recv_recebido >= _recv_total:
		_desde_ack = 0
		rpc_id(1, "confirmar", _recv_recebido)


@rpc("authority", "call_remote", "reliable")
func finalizar_transferencia() -> void:
	if _recv_file == null:
		return
	_recv_file.close()
	_recv_file = null
	# Arquivos pequenos podem terminar antes do buffer inicial: garante o "pronto".
	if not _recv_preparado:
		_recv_preparado = true
		_tela.preparar(ARQUIVO_RECV)
		rpc_id(1, "cliente_pronto")
	_estado("Vídeo recebido por completo (%d KB)." % (_recv_recebido / 1024))


# ============================ Início simultâneo ============================

## CLIENTE -> HOST: avisa que bufferizou e está pronto para começar.
@rpc("any_peer", "call_remote", "reliable")
func cliente_pronto() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	_prontos[peer] = true
	if _reproducao_iniciada:
		# Já começou (cliente atrasado): manda ele tocar agora (ficará atrás, mas toca).
		rpc_id(peer, "iniciar_reproducao")
	else:
		_verificar_inicio()


## Começa quando o vídeo está armado e todos os clientes conectados estão prontos.
func _verificar_inicio() -> void:
	if not multiplayer.is_server() or not _video_armado or _reproducao_iniciada:
		return
	for peer in multiplayer.get_peers():
		if not _prontos.get(peer, false):
			return
	_disparar_inicio()


## Dispara a reprodução no host e em todos os clientes (do zero, simultaneamente).
func _disparar_inicio() -> void:
	if _reproducao_iniciada or not _video_armado:
		return
	_reproducao_iniciada = true
	rpc("iniciar_reproducao")
	_tela.iniciar()
	_estado("Reprodução iniciada (sincronizada).")


## HOST -> CLIENTE: começa a tocar agora.
@rpc("authority", "call_remote", "reliable")
func iniciar_reproducao() -> void:
	_tela.iniciar()


func _estado(texto: String) -> void:
	print("[Cinema] ", texto)
	estado_mudou.emit(texto)
