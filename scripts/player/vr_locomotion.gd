extends CharacterBody3D
## Locomoção VR simples para o cinema.
##
## - Movimento suave: analógico ESQUERDO, relativo à direção do olhar (câmera).
## - Giro em incrementos (snap turn): analógico DIREITO — reduz enjoo em VR.
## - Gravidade: mantém o jogador sobre o piso inclinado (arquibancado) do cinema.
##
## O corpo (cápsula) fica na origem do play space. O caminhar físico do usuário
## (roomscale) move a câmera dentro de uma área pequena; para um cinema isso é
## suficiente. Sincronizar a cápsula com a cabeça pode ser feito numa evolução.

## Velocidade do movimento suave (m/s).
@export var velocidade: float = 2.5
## Ângulo de cada giro do snap turn (graus).
@export var giro_graus: float = 30.0
## Zona morta dos analógicos.
@export var deadzone: float = 0.2

@onready var _camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var _controle_esq: XRController3D = $XROrigin3D/LeftController
@onready var _controle_dir: XRController3D = $XROrigin3D/RightController

var _gravidade: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
# Garante UM giro por inclinada do analógico (precisa voltar ao centro p/ girar de novo).
var _giro_armado: bool = true


func _physics_process(delta: float) -> void:
	_aplicar_gravidade(delta)
	_aplicar_movimento()
	move_and_slide()
	_processar_giro()


func _aplicar_gravidade(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravidade * delta


func _aplicar_movimento() -> void:
	var eixo := _controle_esq.get_vector2(&"primary")
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
