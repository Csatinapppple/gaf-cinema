extends Node3D
## Reproduz um vídeo na tela do cinema.
##
## O vídeo é decodificado num SubViewport (VideoStreamPlayer) e sua textura é
## aplicada à tela via *override da superfície* "screen" do mesh combinado do
## cinema_hall — assim só a tela é afetada, não as paredes/chão/teto.
##
## A tela começa VAZIA (textura original do asset). A sessão de rede chama `preparar()`
## (carrega no frame 0) e depois `iniciar()` (host e clientes começam juntos). Sem autoplay.
##
## Formato: o VideoStreamPlayer nativo do Godot reproduz Ogg Theora (.ogv).

## Repetir o vídeo ao terminar.
@export var repetir: bool = true
## Marque se a imagem aparecer de cabeça para baixo na tela.
@export var inverter_vertical: bool = false
## Marque se a imagem aparecer espelhada horizontalmente.
@export var inverter_horizontal: bool = false
## Nome do material-alvo dentro do GLB.
@export var material_tela: StringName = &"screen"

@onready var _viewport: SubViewport = $SubViewport
@onready var _player: VideoStreamPlayer = $SubViewport/VideoStreamPlayer

var _tela_aplicada: bool = false


func _ready() -> void:
	if repetir:
		_player.finished.connect(_ao_terminar)
	# Sem autoplay: a tela fica com a textura original até um vídeo ser carregado.


func _ao_terminar() -> void:
	_player.play()


## Aplica a textura do SubViewport na superfície da tela uma única vez.
func _garantir_tela() -> void:
	if _tela_aplicada:
		return
	_aplicar_textura_na_tela()
	_tela_aplicada = true


# ----- API pública (usada pela sessão de rede) -----
#
# O seek do VideoStreamPlayer (Theora) não reposiciona de forma confiável, então NÃO
# usamos seek para sincronizar. Em vez disso, host e clientes começam a tocar do zero
# no mesmo instante (preparar → iniciar) e seguem a 1x.

## Carrega o vídeo e deixa pronto no frame 0 (pausado), sem começar a tocar.
func preparar(caminho: String) -> bool:
	if caminho.is_empty():
		return false
	var s := VideoStreamTheora.new()
	s.file = caminho
	_player.stream = s
	_garantir_tela()
	_player.play()
	_player.paused = true  # mostra o início, aguardando o disparo do host
	return true


## Começa (ou retoma) a reprodução do ponto atual.
func iniciar() -> void:
	if _player.stream == null:
		return
	if not _player.is_playing():
		_player.play()
	_player.paused = false


## Pausa/retoma (para sincronizar pausas do host, quando houver controle de pausa).
func definir_pausa(pausado: bool) -> void:
	if _player.stream != null:
		_player.paused = pausado


func tempo_atual() -> float:
	return _player.stream_position


func esta_tocando() -> bool:
	return _player.stream != null and not _player.paused


## Localiza a superfície "screen" no cinema e substitui seu material pela
## textura do SubViewport (tela emissiva/unshaded para não depender da luz da sala).
func _aplicar_textura_na_tela() -> void:
	var alvo := _encontrar_superficie_da_tela(get_tree().current_scene)
	if alvo.is_empty():
		push_warning("[Tela] Material '%s' não encontrado no cinema_hall." % material_tela)
		return

	var mesh_instance: MeshInstance3D = alvo[0]
	var surface: int = alvo[1]
	var tex := _viewport.get_texture()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	# A tela do asset ocupa apenas um sub-retângulo do atlas de UV (ex.: v de 0.56 a 1.0).
	# Remapeamos o vídeo (0..1) para essa região, para que ele preencha a tela inteira,
	# independentemente de como o asset foi modelado.
	var ub := _uv_bounds(mesh_instance.mesh, surface)
	if not ub.is_empty():
		var u0 := float(ub[0])
		var u1 := float(ub[1])
		var v0 := float(ub[2])
		var v1 := float(ub[3])
		var du := maxf(u1 - u0, 1e-5)  # largura da região de UV (u)
		var dv := maxf(v1 - v0, 1e-5)  # altura da região de UV (v)
		var sx := 1.0 / du
		var ox := -u0 / du
		var sy := 1.0 / dv
		var oy := -v0 / dv
		if inverter_vertical:
			sy = -sy
			oy = 1.0 - oy
		if inverter_horizontal:
			sx = -sx
			ox = 1.0 - ox
		mat.uv1_scale = Vector3(sx, sy, 1.0)
		mat.uv1_offset = Vector3(ox, oy, 0.0)
		print("[Tela] UV da tela u[%.3f,%.3f] v[%.3f,%.3f] → remap aplicado."
			% [u0, u1, v0, v1])

	mesh_instance.set_surface_override_material(surface, mat)


## Retorna [u_min, u_max, v_min, v_max] das UVs de uma superfície, ou [] se não houver.
func _uv_bounds(mesh: Mesh, surface: int) -> Array:
	if mesh == null:
		return []
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.is_empty() or arrays[Mesh.ARRAY_TEX_UV] == null:
		return []
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return []
	var u_min := uvs[0].x
	var u_max := uvs[0].x
	var v_min := uvs[0].y
	var v_max := uvs[0].y
	for uv in uvs:
		u_min = minf(u_min, uv.x)
		u_max = maxf(u_max, uv.x)
		v_min = minf(v_min, uv.y)
		v_max = maxf(v_max, uv.y)
	return [u_min, u_max, v_min, v_max]


## Retorna [MeshInstance3D, índice_da_superfície] do material-alvo, ou [] se não achar.
func _encontrar_superficie_da_tela(raiz: Node) -> Array:
	for mi in _coletar_mesh_instances(raiz):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat != null and mat.resource_name == material_tela:
				return [mi, i]
	return []


func _coletar_mesh_instances(raiz: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if raiz is MeshInstance3D:
		out.append(raiz)
	for filho in raiz.get_children():
		out.append_array(_coletar_mesh_instances(filho))
	return out
