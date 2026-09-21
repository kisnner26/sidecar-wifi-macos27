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

## cronología de pruebas

horas locales, 6 y 7 de septiembre. cada fila es una prueba y lo que se midió.

| hora | prueba | resultado |
|---|---|---|
| 23:46 | primer intento, sin cable | `-203`; el ipad anuncia `BLE DuetSync Owner ApplePay PairingMode`, sin `WiFiP2P` |
| 23:49 | segundo intento | `-203`, mismas banderas |
| 00:30 | se conecta el cable usb | sidecar **funciona**; banderas pasan a `BLE iWiFi ... USB ...`; `WiFiP2P` sigue en 0 durante 20 min de sesión activa |
| 00:35 | se desconecta el cable, 3 reintentos (00:35:07, :39, :59) | `-203` las tres veces; el ipad vuelve a anunciar cero capacidades wi-fi |
| 00:42 | se compara la banda de wi-fi | mac y ipad ambos en 2.4 ghz (el mac había estado en 5 ghz minutos antes); señal débil, -72 dbm; el error no cambia |
| 00:45 | compartir internet del ipad reportado activado, luego apagado | 28 anuncios idénticos en 4 min, `WiFiP2P: 0`, `iWiFi: 0`, `AirDropUsable: 0` |
| 00:47 | restablecer ajustes de red en el ipad | 124 anuncios en 6 min (se re-registra), `AirDropUsable: 2`, `WiFiP2P` y `iWiFi` siguen en 0 |
| 00:49 y 00:54 | nuevos intentos | `-203`; ahora el mac tampoco ve la bandera `USB` |
| 00:55 | se revisa el cable | finder ve el ipad tras confiar de nuevo, pero `en9` queda huérfana y no hay servicio "ipad usb" |
| 00:59 | estado final | wi-fi del mac on y conectado; ipad en `USB: 0`, `iWiFi: 0`, `WiFiP2P: 0`; la sesión termina proponiendo reiniciar ambos |

## qué se descubrió probando

1. **por cable funciona sin `WiFiP2P`.** sidecar por usb no necesita el canal peer-to-peer, así que el stack completo (apple id, emparejamiento, video) está bien. el fallo es solo del transporte inalámbrico.
2. **el ipad nunca ofrece `WiFiP2P`**, ni antes ni después de apagar compartir internet, cambiar de banda o restablecer la red.
3. **conectado por cable el ipad sí anuncia `iWiFi`; desconectado no.** desconectado no anuncia ninguna capacidad wi-fi, aunque en ajustes se vea unido a la red.
4. **el error de macos es literal.** `SidecarErrorDeviceWiFiNotEnabled` coincide con lo medido: el ipad no reporta wi-fi disponible para sidecar.
5. **restablecer ajustes de red no arregla y rompe el cable.** cambia el comportamiento de los anuncios pero no devuelve `WiFiP2P`, y elimina el camino usb hasta reconstruir la confianza.
6. **la banda no importa.** falló igual en 5 y en 2.4 ghz.

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
