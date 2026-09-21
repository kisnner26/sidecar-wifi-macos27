# sidecar-wifi-macos27

investigación de por qué sidecar no conecta de forma inalámbrica entre un macbook pro y un ipad pro en macos 27 / ipados 27 (seed), aunque por cable sí funciona.

estado: **sin resolver**. aquí queda lo que se midió, lo que se descartó y lo que falta probar.

## resumen

| | |
|---|---|
| mac | macbookpro17,1 (m1, 2020) · macos 27.0 (26a5425a) |
| ipad | ipad13,10 (ipad pro 12.9" 5ª gen, wi-fi + cellular) · ipados 27.0 |
| error | `SidecarErrorDomain -203 "SidecarErrorDeviceWiFiNotEnabled"` |
| por cable | funciona |
| por wi-fi | falla siempre, mismo error |

el mac está sano: wi-fi, bluetooth y awdl arriba, lee sin problema el `WiFiP2P` de otro dispositivo del mismo apple id. el ipad nunca anuncia `WiFiP2P` por bluetooth (0 veces en horas de logs), y sin esa capacidad el mac aborta la sesión antes de intentar el video.

detalle completo, cronología y comandos para reproducir en [notes/investigacion.md](notes/investigacion.md).

## reproducir el diagnóstico

```bash
# errores de sidecar (usar la ruta completa, `log` a secas choca con un builtin de zsh)
/usr/bin/log show --last 10m --style compact \
  --predicate 'subsystem CONTAINS[c] "sidecar"' | grep -E "Sidecar Started|-203|unrecoverable"

# qué capacidades anuncia el ipad; buscar WiFiP2P
/usr/bin/log show --last 5m --style compact \
  --predicate 'subsystem CONTAINS[c] "sidecar"' | grep "Device Changed"
```

## contribuir

si viste el mismo `-203` con ipad anunciando solo `<BLE DuetSync Owner ApplePay ...>` sin `WiFiP2P`, abre un issue con tu modelo de mac, de ipad y versiones.
