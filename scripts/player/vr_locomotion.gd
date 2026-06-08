extends CharacterBody3D
## Locomoção VR do cinema.
##
## - Caminhar físico (roomscale): a cápsula de colisão segue a cabeça (câmera),
##   respeitando paredes/poltronas.
## - Movimento suave: analógico ESQUERDO, relativo à direção do olhar.
## - Giro em incrementos (snap turn): analógico DIREITO — reduz enjoo.
## - Sobe/desce a arquibancada via "stair stepping" (degraus de ~0,5 m).
## - Gravidade: mantém o jogador apoiado no piso.

## Velocidade do movimento suave (m/s).
@export var velocidade: float = 2.5
## Ângulo de cada giro do snap turn (graus).
@export var giro_graus: float = 30.0
## Zona morta dos analógicos.
@export var deadzone: float = 0.2
## Altura máxima de degrau que o jogador consegue subir/descer.
@export var altura_max_degrau: float = 0.6
## Sensibilidade do mouse no modo desktop (flat).
@export var sensibilidade_mouse: float = 0.0025

@onready var _origin: XROrigin3D = $XROrigin3D
@onready var _camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var _controle_esq: XRController3D = $XROrigin3D/LeftController
@onready var _controle_dir: XRController3D = $XROrigin3D/RightController
@onready var _forma: CollisionShape3D = $CollisionShape3D

var _gravidade: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
# Garante UM giro por inclinada do analógico (precisa voltar ao centro p/ girar de novo).
var _giro_armado: bool = true
# Raio da cápsula (lido em _ready); a sonda de degrau precisa ir ALÉM do corpo.
var _raio: float = 0.25
# Inclinação (pitch) da câmera no modo flat (mouse).
var _pitch: float = 0.0


func _ready() -> void:
	# Publica o rig em grupos para o avatar de rede local copiar as poses.
	_camera.add_to_group(&"xr_head")
	_controle_esq.add_to_group(&"xr_hand_left")
	_controle_dir.add_to_group(&"xr_hand_right")
	# Lê o raio real da cápsula para dimensionar a sonda de degrau.
	if _forma != null and _forma.shape is CapsuleShape3D:
		_raio = (_forma.shape as CapsuleShape3D).radius
	# Faz a cápsula "grudar" no chão ao descer degraus (descida suave).
	floor_snap_length = maxf(floor_snap_length, minf(altura_max_degrau, 1.5))


func _physics_process(delta: float) -> void:
	_sincronizar_roomscale()
	_aplicar_gravidade(delta)
	_aplicar_movimento()
	_tentar_subir_degrau()
	move_and_slide()
	_processar_giro()


## Move a cápsula para ficar sob a cabeça (caminhar físico), compensando a origem
## para que a câmera não "ande junto". Em desktop (flat) a câmera fica sobre a
## origem, então isto vira no-op.
func _sincronizar_roomscale() -> void:
	var cam := _camera.global_position
	var desloc := Vector3(cam.x - global_position.x, 0.0, cam.z - global_position.z)
	if desloc.length() < 0.0001:
		return
	var antes := global_position
	move_and_collide(desloc)
	var movido := global_position - antes
	_origin.global_position -= movido


func _aplicar_gravidade(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravidade * delta


func _aplicar_movimento() -> void:
	# Em desktop (flat) usa o teclado; em VR, o analógico esquerdo.
	var eixo := _ler_teclado() if _flat() else _controle_esq.get_vector2(&"primary")
	if eixo.length() > 1.0:
		eixo = eixo.normalized()
	if eixo.length() < deadzone:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	# Direções no plano horizontal, a partir da orientação da câmera.
	var base := _camera.global_transform.basis
	var frente := -base.z
	var lado := base.x
	frente.y = 0.0
	lado.y = 0.0
	frente = frente.normalized()
	lado = lado.normalized()
	var mov := (lado * eixo.x + frente * eixo.y) * velocidade
	velocity.x = mov.x
	velocity.z = mov.z


## True quando rodando sem headset (renderização "flat" no desktop).
func _flat() -> bool:
	return not get_viewport().use_xr


## Vetor de movimento por teclado (WASD), no padrão (x = strafe, y = frente/trás).
func _ler_teclado() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	return v


## Olhar com mouse no modo flat: clique esquerdo captura, Esc libera (para usar o lobby).
func _unhandled_input(event: InputEvent) -> void:
	if not _flat():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		# Giro (yaw) no corpo; inclinação (pitch) na câmera.
		rotate_y(-mm.relative.x * sensibilidade_mouse)
		_pitch = clampf(_pitch - mm.relative.y * sensibilidade_mouse, deg_to_rad(-89.0), deg_to_rad(89.0))
		_camera.rotation.x = _pitch


## Sobe um degrau logo à frente, se houver um dentro de `altura_max_degrau`.
## Sonda ALÉM do raio da cápsula (senão o corpo nunca encosta no topo do degrau) e,
## ao achar um degrau válido, eleva o corpo só em Y — o avanço horizontal fica a cargo
## do move_and_slide do mesmo frame, que então passa por cima do degrau.
func _tentar_subir_degrau() -> void:
	if not is_on_floor():
		return
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length() < 0.01:
		return
	var dir := horiz.normalized()
	var folga := clampf(altura_max_degrau, 0.1, 1.5)  # altura da sonda (limita teto)
	# Ponto à frente (passando do corpo) e elevado, para achar o topo do degrau.
	var t := global_transform
	t.origin += dir * (_raio + 0.2) + Vector3.UP * folga
	var col := KinematicCollision3D.new()
	if not test_move(t, Vector3.DOWN * (folga + 0.1), col):
		return  # nada abaixo: não é um degrau (é vão/parede alta)
	var topo_y := (t.origin + col.get_travel()).y
	var altura := topo_y - global_position.y
	if altura <= 0.05 or altura > altura_max_degrau:
		return  # plano demais, ou alto demais para subir
	# Só sobe se o topo for "chão" (não uma parede/rampa íngreme).
	if col.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return
	global_position.y = topo_y + 0.02


func _processar_giro() -> void:
	var gx := _controle_dir.get_vector2(&"primary").x
	if absf(gx) < deadzone:
		_giro_armado = true
	elif _giro_armado:
		_giro_armado = false
		_girar(-signf(gx) * deg_to_rad(giro_graus))


## Gira o jogador em torno da câmera (não da origem), mantendo a cabeça no lugar.
func _girar(rad: float) -> void:
	var pivo := _camera.global_position
	var t := global_transform
	t.origin -= pivo
	t = t.rotated(Vector3.UP, rad)
	t.origin += pivo
	global_transform = t
