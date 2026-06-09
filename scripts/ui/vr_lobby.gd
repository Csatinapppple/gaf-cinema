extends Node3D
## Lobby em VR (world-space): teclado numérico apontável para digitar o IP do host
## e botões Hospedar/Entrar. Construído por código. Interage via vr_pointer.gd.
##
## No desktop (flat) este painel se esconde — lá usa-se o lobby 2D (lobby_ui.gd).

const COR_BOTAO := Color(0.2, 0.4, 0.9)
const COR_HOST := Color(0.2, 0.5, 0.25)
const COR_JOIN := Color(0.55, 0.4, 0.12)
const COR_LIMPAR := Color(0.45, 0.25, 0.25)
const TAM := 0.1     # lado do botão
const ESP := 0.115   # espaçamento da grade

var _ip := ""
var _display: Label3D
var _status: Label3D


func _ready() -> void:
	add_to_group(&"vr_lobby")
	_construir()
	Net.estado_mudou.connect(func(t: String) -> void: _status.text = t)
	multiplayer.connected_to_server.connect(_ao_conectar)
	multiplayer.connection_failed.connect(func() -> void: _status.text = "Falha na conexão. Confira o IP do host.")
	multiplayer.server_disconnected.connect(func() -> void:
		_status.text = "Servidor caiu."
		visible = true)
	# Apenas em VR — no desktop usa-se o lobby 2D.
	await get_tree().process_frame
	if not get_viewport().use_xr:
		visible = false
		set_process(false)


func _ao_conectar() -> void:
	_status.text = "Conectado!"
	_ocultar()


## Chamado pelo ponteiro quando um botão é clicado.
func acionar(acao: String) -> void:
	match acao:
		"back":
			_ip = _ip.substr(0, maxi(0, _ip.length() - 1))
		"clear":
			_ip = ""
		"host":
			Net.hospedar()
			_ocultar()
		"join":
			Net.entrar(_ip)
		_:
			if _ip.length() < 21:
				_ip += acao
	_atualizar()


func _atualizar() -> void:
	_display.text = "IP: " + _ip


func _ocultar() -> void:
	visible = false


func _construir() -> void:
	_titulo("Cinema Virtual — Conectar", 0.40, 0.0026)
	_display = _titulo("IP: " + _ip, 0.30, 0.0040)
	_status = _titulo("Aponte e use o gatilho", 0.235, 0.0022)

	var teclas := [
		["7", "8", "9"],
		["4", "5", "6"],
		["1", "2", "3"],
		[".", "0", "back"],
	]
	var y := 0.12
	for linha in teclas:
		var x := -ESP
		for t in linha:
			var rotulo: String = "<" if t == "back" else t
			_botao(rotulo, t, Vector3(x, y, 0.0), COR_BOTAO, TAM, 0.0035)
			x += ESP
		y -= ESP

	# Linha de ações (botões mais largos, espaçados e com texto menor)
	var ya := y - 0.06
	_botao("Hospedar", "host", Vector3(-0.21, ya, 0.0), COR_HOST, 0.2, 0.0020)
	_botao("Entrar", "join", Vector3(0.0, ya, 0.0), COR_JOIN, 0.2, 0.0020)
	_botao("Limpar", "clear", Vector3(0.21, ya, 0.0), COR_LIMPAR, 0.2, 0.0020)


func _titulo(txt: String, y: float, px: float) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.pixel_size = px
	l.position = Vector3(0, y, 0.01)
	add_child(l)
	return l


func _botao(rotulo: String, acao: String, pos: Vector3, cor: Color, largura: float, px: float) -> void:
	var area := Area3D.new()
	area.position = pos
	area.add_to_group(&"vr_button")
	area.set_meta("acao", acao)
	area.set_meta("cor", cor)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(largura, TAM, 0.03)
	col.shape = box
	area.add_child(col)

	var fundo := MeshInstance3D.new()
	fundo.name = "Fundo"
	var quad := QuadMesh.new()
	quad.size = Vector2(largura, TAM)
	fundo.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = cor
	fundo.material_override = mat
	area.add_child(fundo)

	var l := Label3D.new()
	l.text = rotulo
	l.pixel_size = px
	l.position = Vector3(0, 0, 0.02)
	area.add_child(l)

	add_child(area)
