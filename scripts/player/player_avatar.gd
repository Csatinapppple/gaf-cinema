extends Node3D
## Avatar de rede (placeholder): cabeça + duas mãos.
##
## A AUTORIDADE (peer dono deste avatar) copia, a cada frame, as poses do rig XR
## local (câmera + controles, achados por grupo) para Head/HandL/HandR. Os demais
## peers apenas exibem essas poses, recebidas via MultiplayerSynchronizer.
##
## O nome do nó é o id do peer dono (definido no spawn), usado para a autoridade.

@onready var _head: Node3D = $Head
@onready var _hand_l: Node3D = $HandL
@onready var _hand_r: Node3D = $HandR
@onready var _sync: MultiplayerSynchronizer = $MultiplayerSynchronizer


func _ready() -> void:
	set_multiplayer_authority(name.to_int())
	_configurar_replicacao()
	if is_multiplayer_authority():
		# Não renderiza a própria cabeça (ficaria colada na câmera).
		_head.visible = false


func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var head := get_tree().get_first_node_in_group(&"xr_head") as Node3D
	var mao_e := get_tree().get_first_node_in_group(&"xr_hand_left") as Node3D
	var mao_d := get_tree().get_first_node_in_group(&"xr_hand_right") as Node3D
	if head != null:
		_head.global_transform = head.global_transform
	if mao_e != null:
		_hand_l.global_transform = mao_e.global_transform
	if mao_d != null:
		_hand_r.global_transform = mao_d.global_transform


## Configura via código quais propriedades são replicadas (evita versionar o recurso).
func _configurar_replicacao() -> void:
	var cfg := SceneReplicationConfig.new()
	cfg.add_property(NodePath("Head:transform"))
	cfg.add_property(NodePath("HandL:transform"))
	cfg.add_property(NodePath("HandR:transform"))
	_sync.replication_config = cfg
