extends Node
## Cria/remove avatares de jogadores conforme entram e saem da sessão.
##
## Roda em todos os peers, mas só o SERVIDOR instancia avatares (sob o nó "Players").
## O MultiplayerSpawner replica esses avatares para os clientes automaticamente,
## inclusive para quem conecta depois.

## Nó sob o qual os avatares são adicionados (alvo do MultiplayerSpawner).
@export var caminho_jogadores: NodePath
## Cena do avatar a instanciar por jogador.
@export var cena_avatar: PackedScene

@onready var _jogadores: Node = get_node(caminho_jogadores)


func _ready() -> void:
	Net.hospedou.connect(_iniciar_servidor)
	multiplayer.peer_connected.connect(_ao_conectar)
	multiplayer.peer_disconnected.connect(_ao_desconectar)


## Ao virar servidor, cria o avatar do próprio host (peer id 1).
func _iniciar_servidor() -> void:
	_spawn(1)


func _ao_conectar(id: int) -> void:
	if multiplayer.is_server():
		_spawn(id)


func _ao_desconectar(id: int) -> void:
	if multiplayer.is_server():
		var n := _jogadores.get_node_or_null(str(id))
		if n != null:
			n.queue_free()


func _spawn(id: int) -> void:
	if cena_avatar == null or _jogadores.has_node(str(id)):
		return
	var avatar := cena_avatar.instantiate()
	avatar.name = str(id)
	_jogadores.add_child(avatar, true)
	print("[Net] Avatar do jogador %d criado." % id)
