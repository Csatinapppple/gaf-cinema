extends CanvasLayer
## UI de rede (desktop) e controle de vídeo do host.
##
## - Painel de conexão: hospedar ou entrar por IP.
## - Painel do host (só aparece para quem hospeda): escolher o vídeo (URL do YouTube)
##   ou testar com um .ogv local.
##
## Em VR esta UI de tela não aparece no headset — monte a sessão no desktop e então
## coloque o headset. UI em world-space p/ VR é evolução.
##
## Argumentos de linha de comando (após `--`), para testes headless:
##   -- --host                → hospeda
##   -- --join=127.0.0.1      → entra no IP
##   -- --video-local         → (com --host) carrega o .ogv local e transmite

@onready var _ip: LineEdit = $Panel/VBox/IP
@onready var _status: Label = $Panel/VBox/Status
@onready var _painel_host: PanelContainer = $HostPanel
@onready var _url: LineEdit = $HostPanel/VBox/URL
@onready var _video_status: Label = $HostPanel/VBox/VideoStatus
@onready var _sessao: Node = get_node("../CinemaSession")


func _ready() -> void:
	_painel_host.visible = false
	Net.estado_mudou.connect(_ao_estado)
	_sessao.estado_mudou.connect(func(t: String) -> void: _video_status.text = t)
	$Panel/VBox/HBox/Hospedar.pressed.connect(_hospedar)
	$Panel/VBox/HBox/Entrar.pressed.connect(_entrar)
	$HostPanel/VBox/HBox/Carregar.pressed.connect(_carregar)
	$HostPanel/VBox/HBox/TestarLocal.pressed.connect(_testar_local)
	multiplayer.connected_to_server.connect(_esconder_conexao)
	multiplayer.connection_failed.connect(func() -> void: _ao_estado("Falha na conexão."))
	multiplayer.server_disconnected.connect(func() -> void: $Panel.visible = true)
	_processar_argumentos()
	# Em VR usa-se o lobby world-space (vr_lobby.gd); esconde esta UI 2D de tela.
	await get_tree().process_frame
	if get_viewport().use_xr:
		visible = false


func _hospedar() -> void:
	if Net.hospedar() == OK:
		_esconder_conexao()
		_painel_host.visible = true


func _entrar() -> void:
	Net.entrar(_ip.text)


func _carregar() -> void:
	_sessao.host_carregar_youtube(_url.text)


func _testar_local() -> void:
	_sessao.host_carregar_arquivo("res://assets/videos/teste00.ogv")


func _esconder_conexao() -> void:
	$Panel.visible = false


func _ao_estado(texto: String) -> void:
	_status.text = texto


func _processar_argumentos() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--host":
			_hospedar()
		elif arg.begins_with("--join="):
			_ip.text = arg.split("=")[1]
			_entrar()
	if args.has("--video-local"):
		_testar_local()
