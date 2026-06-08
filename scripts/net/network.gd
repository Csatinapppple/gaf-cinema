extends Node
## Gerenciador de rede — LAN / IP direto (listen-server) usando a API de alto nível
## do Godot (ENetMultiplayerPeer). Um jogador hospeda; os outros entram pelo IP.
##
## Autoload: acessível globalmente como `Net`.

const PORTA_PADRAO := 7777
const MAX_JOGADORES := 8

## Emitido a cada mudança de estado (para a UI mostrar).
signal estado_mudou(texto: String)
## Emitido quando ESTE peer passou a hospedar (servidor criado com sucesso).
signal hospedou


func hospedar(porta: int = PORTA_PADRAO) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(porta, MAX_JOGADORES)
	if err != OK:
		_estado("Falha ao hospedar (%s)." % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	_estado("Hospedando na porta %d (você é o servidor)." % porta)
	hospedou.emit()
	return OK


func entrar(ip: String, porta: int = PORTA_PADRAO) -> Error:
	if ip.strip_edges().is_empty():
		_estado("Informe o IP do servidor.")
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, porta)
	if err != OK:
		_estado("Falha ao conectar (%s)." % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	_estado("Conectando a %s:%d..." % [ip, porta])
	return OK


func sair() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_estado("Desconectado.")


func esta_ativo() -> bool:
	return multiplayer.multiplayer_peer != null


func _estado(texto: String) -> void:
	print("[Net] ", texto)
	estado_mudou.emit(texto)
