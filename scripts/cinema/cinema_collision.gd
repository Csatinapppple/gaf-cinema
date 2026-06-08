extends Node3D
## Gera colisão estática para a estrutura do cinema (chão inclinado, paredes, teto),
## para que o jogador caminhe sobre o piso e não atravesse as paredes.
##
## A geometria estrutural está num único mesh combinado (materiais wood/tile/floor/
## screen/ceiling). Geramos um collider trimesh dele em tempo de execução, evitando
## ter de versionar um recurso de colisão à parte.
##
## Observação: as poltronas são meshes separados e ficam SEM colisão por enquanto
## (o jogador as atravessa) — colisão das cadeiras pode ser adicionada depois.

## Material usado para identificar o mesh estrutural dentro do GLB.
@export var material_estrutura: StringName = &"floor"


func _ready() -> void:
	var mi := _achar_mesh_com_material(self, material_estrutura)
	if mi == null:
		push_warning("[Cinema] Mesh estrutural ('%s') não encontrado — sem colisão." % material_estrutura)
		return
	mi.create_trimesh_collision()
	print("[Cinema] Colisão estática gerada a partir de '%s'." % mi.name)


## Busca em profundidade o primeiro MeshInstance3D que use o material informado.
func _achar_mesh_com_material(raiz: Node, mat_nome: StringName) -> MeshInstance3D:
	var pilha: Array[Node] = [raiz]
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(i)
					if m != null and m.resource_name == mat_nome:
						return mi
		for c in n.get_children():
			pilha.append(c)
	return null
