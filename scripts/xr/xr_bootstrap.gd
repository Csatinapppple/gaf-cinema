extends Node3D
## Bootstrap de XR da cena principal.
##
## Inicializa o OpenXR quando há um runtime/headset disponível (Quest standalone
## ou PCVR via Quest Link/Air Link). Em desktop sem headset, segue em modo "flat"
## (janela 3D normal) para permitir testes rápidos sem VR.

@onready var _xr_interface: XRInterface = XRServer.find_interface("OpenXR")


func _ready() -> void:
	if _xr_interface and _xr_interface.is_initialized():
		print("[XR] OpenXR inicializado — renderizando em VR.")
		# Ativa a renderização estereoscópica neste viewport.
		get_viewport().use_xr = true
		# Em VR o compositor do headset controla o sincronismo; desligar o V-Sync
		# do SO evita "double sync" e perda de frames.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		print("[XR] OpenXR indisponível — modo desktop (flat) para testes.")
