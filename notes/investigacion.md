# investigación: sidecar inalámbrico falla con -203

datos del 6 y 7 de septiembre de 2026. identificadores personales (mac addresses, seriales, nombre de la red, ids de dispositivos) quitados o generalizados.

## entorno

- mac: macbookpro17,1, macos 27.0, build 26a5425a (seed)
- ipad: ipad13,10, ipados 27.0, con plan celular (tiene módem)
- ambos en el mismo apple id, wi-fi en la misma red doméstica
- otras cosas activas en el mac: dos vpn (protonvpn, localdevvpn) con varias interfaces `utun`

## síntoma

al elegir el ipad desde screen mirroring, macos muestra un diálogo diciendo que el wi-fi del ipad no está disponible / no está en uso para compartir internet. el error real en los logs:

```
SidecarRelay: Open Session Failed: SidecarErrorDomain (-203)
SidecarSession connectWithTransport:reconnectToSession: SidecarErrorDomain (-203)
Encountered unrecoverable error: SidecarErrorDomain Code=-203 "SidecarErrorDeviceWiFiNotEnabled"
```

reproducible en cada intento (se probaron al menos 6).

## evidencia principal: las banderas que anuncia el ipad

`SidecarRelay` (subsistema `com.apple.sidecar:rapport`) registra las capacidades que cada dispositivo anuncia por bluetooth:

| dispositivo | banderas |
|---|---|
| otro dispositivo del mismo apple id | `BLE DuetSync WiFiP2P Owner ApplePay ...` |
| ipad, desconectado | `BLE DuetSync Owner ApplePay PairingMode ...` |
| ipad, con cable usb | `BLE iWiFi DuetSync Owner ApplePay USB PairingMode ...` |

- en 6 horas de logs el ipad anunció `WiFiP2P` **0 veces**.
- desconectado no anuncia ni `WiFiP2P` ni `iWiFi`: ninguna capacidad wi-fi.
- alguna vez sí anunció `AirDropUsable`, así que la radio funcionó antes en la ventana observada.
- el mac lee `WiFiP2P` del otro dispositivo sin problema, así que el descubrimiento (rapport) del lado mac funciona.

## descartado

| hipótesis | por qué se descarta |
|---|---|
| wi-fi o bluetooth del mac caídos | wi-fi conectado, bluetooth on, `awdl0` up/running |
| vpn interceptando la ruta | ruta por defecto limpia por el router |
| compartir internet (nat) del mac | apagado |
| incompatibilidad de modelos | macbookpro17,1 e ipad13,10 son compatibles con sidecar |
| apple id / emparejamiento roto | el ipad aparece con `Owner` y `MeDeviceIsMe` |
| `PairingMode` constante como causa | aparece siempre en el ipad; parece estado normal del anuncio, no un fallo |
| banda 2.4 vs 5 ghz | ambos en 2.4 ghz y siguió fallando |
| ipad sin cable no autenticado | por cable sí funcionó, todo el stack de sidecar responde |

## sin confirmar

- **compartir internet del ipad**: en un momento apareció activado; después se apagó y el síntoma siguió igual. el ipad ni siquiera puede usar compartir internet en la práctica. no se pudo verificar el estado real del interruptor desde el mac.
- **bug del seed de 27.0**: hipótesis por descarte, sin evidencia directa. no se reportó todavía en feedback assistant.
- **prueba de airdrop** (ipad → mac, sin cable): usa el mismo awdl que sidecar. se pidió pero no quedó registrado el resultado.

## efecto colateral: restablecer ajustes de red en el ipad

para limpiar un supuesto estado atascado de la radio se hizo *restablecer ajustes de red* en el ipad. resultado: **también dejó de funcionar el cable**.

- el ipad perdió las banderas `USB` e `iWiFi` (olvidó redes wi-fi y la confianza con el mac).
- finder volvió a ver el ipad tras aceptar de nuevo "confiar en esta computadora", pero sidecar siguió sin transporte.
- macos había creado la interfaz `en9` (link-local, `169.254.x.x`) pero no un servicio de red "ipad usb": quedó huérfana. existía un servicio "iphone usb" viejo.

lección: ese reset es de bajo valor diagnóstico aquí y rompe el plan b. no recomendarlo antes de probar reinicio y airdrop.

## notas técnicas menores

- en macos 27, `networksetup -getairportnetwork en0` da falso negativo (dice "not associated" estando conectado). usar `system_profiler SPAirPortDataType`.
- el panel de wi-fi de ajustes del sistema también mostró un aviso obsoleto ("turn on wi-fi") con el wi-fi conectado.
- `log show` a secas falla en zsh (`too many arguments`, choca con un builtin). usar `/usr/bin/log`.

## siguiente

1. reiniciar ipad y mac (en ese orden), reconectar el ipad a la red, aceptar la confianza por cable de nuevo.
2. probar airdrop ipad → mac sin cable y comparar con la bandera `AirDropUsable`.
3. probar con la vpn `localdevvpn` desactivada, por si sus interfaces `utun` afectan awdl.
4. si `WiFiP2P` sigue en 0 con todo lo anterior: reporte en feedback assistant con esta evidencia.
