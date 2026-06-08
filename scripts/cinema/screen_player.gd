extends Node3D
## Reproduz um vídeo na tela do cinema.
##
## O vídeo é decodificado num SubViewport (VideoStreamPlayer) e sua textura é
## aplicada à tela via *override da superfície* "screen" do mesh combinado do
## cinema_hall — assim só a tela é afetada, não as paredes/chão/teto.
##
## Origem do vídeo:
##   1. `video_externo`  — arquivo "de fora da aplicação" (no Quest: /sdcard/Movies/...).
##   2. `video_fallback` — recurso .ogv embarcado no projeto (usado em desktop/teste).
## Se nenhum existir, a textura original da tela (screen.png do asset) é mantida.
##
## Formato: o VideoStreamPlayer nativo do Godot reproduz Ogg Theora (.ogv).
## Converter com: ffmpeg -i entrada.mp4 -q:v 7 -q:a 5 saida.ogv

## Caminho absoluto no dispositivo. No Quest 2 use algo como
## "/sdcard/Movies/cinema/filme.ogv" e copie o arquivo via `adb push`.
@export var video_externo: String = "/sdcard/Movies/cinema/filme.ogv"
## Vídeo embarcado usado como fallback (principalmente em desktop).
@export_file("*.ogv") var video_fallback: String = "res://assets/videos/teste00.ogv"
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


func _ready() -> void:
	var stream := _obter_stream()
	if stream == null:
		print("[Tela] Nenhum vídeo encontrado — mantendo a textura original da tela.")
		return

	_player.stream = stream
	if repetir:
		_player.finished.connect(func() -> void: _player.play())
	_player.play()
	_aplicar_textura_na_tela()
	print("[Tela] Reproduzindo vídeo na tela do cinema.")


## Tenta o vídeo externo; se indisponível, cai para o fallback embarcado.
func _obter_stream() -> VideoStream:
	if not video_externo.is_empty() and FileAccess.file_exists(video_externo):
		var s := VideoStreamTheora.new()
		s.file = video_externo
		return s
	if not video_fallback.is_empty() and ResourceLoader.exists(video_fallback):
		return load(video_fallback)
	return null


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
