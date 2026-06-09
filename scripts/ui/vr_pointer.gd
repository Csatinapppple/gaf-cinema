extends Node3D
## Ponteiro laser (controle direito) para interagir com a UI em VR (world-space).
##
## Lança um RayCast3D para frente (-Z do controle); destaca o botão sob a mira e, ao
## apertar o gatilho, "clica" nele chamando `acionar(acao)` no nó do grupo "vr_lobby".
## Os botões são Area3D no grupo "vr_button" com metadados "acao" e "cor".

const COMPRIMENTO := 5.0
const COR_NORMAL := Color(0.2, 0.4, 0.9)
const COR_HOVER := Color(0.35, 0.85, 1.0)

var _controle: XRController3D
var _ray: RayCast3D
var _marca: MeshInstance3D
var _alvo: Area3D = null


func _ready() -> void:
	_controle = get_parent() as XRController3D
	if _controle != null:
		_controle.button_pressed.connect(_ao_botao)

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -COMPRIMENTO)
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = false
	add_child(_ray)

	# Linha visível do raio (cilindro fino ao longo de -Z).
	var linha := MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = 0.004
	cil.bottom_radius = 0.004
	cil.height = COMPRIMENTO
	linha.mesh = cil
	linha.rotation_degrees = Vector3(-90, 0, 0)
	linha.position = Vector3(0, 0, -COMPRIMENTO / 2.0)
	linha.material_override = _mat(COR_NORMAL)
	add_child(linha)

	# Marca no ponto de mira (esfera em espaço global).
	_marca = MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = 0.012
	esfera.height = 0.024
	_marca.mesh = esfera
	_marca.material_override = _mat(COR_HOVER)
	_marca.top_level = true
	add_child(_marca)


func _process(_delta: float) -> void:
	if _ray == null:
		return
	_ray.force_raycast_update()
	var novo: Area3D = null
	if _ray.is_colliding():
		_marca.visible = true
		_marca.global_position = _ray.get_collision_point()
		var c := _ray.get_collider()
		if c is Area3D and (c as Area3D).is_in_group(&"vr_button"):
			novo = c as Area3D
	else:
		_marca.visible = false
	if novo != _alvo:
		_destacar(_alvo, false)
		_alvo = novo
		_destacar(_alvo, true)


func _ao_botao(nome: String) -> void:
	if nome != "trigger_click":
		return
	if _alvo != null:
		var lobby := get_tree().get_first_node_in_group(&"vr_lobby")
		if lobby != null and lobby.has_method("acionar"):
			lobby.acionar(_alvo.get_meta("acao"))


func _destacar(area: Area3D, ligado: bool) -> void:
	if area == null:
		return
	var fundo := area.get_node_or_null("Fundo") as MeshInstance3D
	if fundo != null and fundo.material_override is StandardMaterial3D:
		var cor: Color = COR_HOVER if ligado else area.get_meta("cor", COR_NORMAL)
		(fundo.material_override as StandardMaterial3D).albedo_color = cor


func _mat(cor: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = cor
	return m
