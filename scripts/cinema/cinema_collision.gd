extends Node3D
## Gera colisão estática para o cinema em tempo de execução.
##
## Cria colliders trimesh para:
##   - a estrutura (mesh combinado com chão inclinado / arquibancada, paredes, teto);
##   - as poltronas (meshes separados das fileiras).
##
## Identificamos os meshes pelos nomes de material, evitando versionar recursos de
## colisão à parte. Decoração/luminárias ficam sem colisão (não atrapalham o caminhar).

## Meshes que usem qualquer um destes materiais recebem colisão.
@export var materiais_colisao: Array[StringName] = [&"floor", &"armchair"]


func _ready() -> void:
	var alvos := _meshes_com_materiais(self, materiais_colisao)
	if alvos.is_empty():
		push_warning("[Cinema] Nenhum mesh com os materiais %s — sem colisão." % str(materiais_colisao))
		return
	for mi in alvos:
		mi.create_trimesh_collision()
	print("[Cinema] Colisão estática gerada para %d mesh(es)." % alvos.size())


func _meshes_com_materiais(raiz: Node, mats: Array[StringName]) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var pilha: Array[Node] = [raiz]
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null and _usa_algum_material(mi.mesh, mats):
				out.append(mi)
		for c in n.get_children():
			pilha.append(c)
	return out


func _usa_algum_material(mesh: Mesh, mats: Array[StringName]) -> bool:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m != null and mats.has(m.resource_name):
			return true
	return false
