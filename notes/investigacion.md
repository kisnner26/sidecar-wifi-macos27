# investigación: sidecar inalámbrico falla con -203

estado: **resuelto** el 21 de septiembre de 2026. la causa era el inicio de sesión de icloud del ipad, no el wi-fi.

## entorno

| | |
|---|---|
| mac | `MacBookPro17,1` (m1, 2020) · macos 27.0 `26A5425a` el 6-7 de sep, macos 27.2 beta 1 `26B5086k` el 21 de sep |
| ipad | `iPad13,10` (ipad pro 12.9", 5ª gen, wi-fi + celular) · ipados 27.0 `24A435` → 27.2 `24B5084k` el 21 de sep |
| conexión | mismo wi-fi doméstico; el mac en 5 ghz (canal 44) de forma continua |
| por cable | sidecar siempre funcionó |

## síntoma

al elegir el ipad en pantalla de macos, el diálogo dice que sidecar no puede conectar de forma inalámbrica porque el wi-fi del ipad no está disponible. el registro dice:

```
SidecarRelay: Connecting to IDS <ipad> 'com.apple.sidecar.display'
SidecarRelay: Open Session Failed: SidecarErrorDomain (-203)     ← 25 ms después
SidecarDisplayAgent: Encountered unrecoverable error: SidecarErrorDomain Code=-203 "SidecarErrorDeviceWiFiNotEnabled"
```

el intento falla antes de tocar la red: es una comprobación local (ver [arquitectura.md](arquitectura.md)).

## la causa, con evidencia del propio ipad

registros del ipad (1.1 gb recopilados con `log collect --device-udid …`, extractos enmascarados en [evidence/ipad-por-que-no-anuncia-wifip2p.txt](../evidence/ipad-por-que-no-anuncia-wifip2p.txt)):

1. el ipad **explica por qué no pone el bit**, en `sharingd`, cada ~100 ms:
   `WiFiP2P bit is not set, WiFi state: Connected, hostAP: NO, NearbyAction scan: on, Manatee: NO`
   el wi-fi estaba conectado, no era punto de acceso y el escaneo estaba activo. lo único negativo es `Manatee: NO`.
2. manatee (cifrado del llavero de icloud) estaba caído: `Manatee not available due to circle failure … CDPStateError Code=-5403`, con `securityd` diciendo `trust status: (excluded)` y `updated account trust state: UNTRUSTED`.
3. el aviso `com.apple.AAFollowUpIdentifier.RenewCredentials` («renovar credenciales») ya estaba pendiente cada vez que ajustes lo leyó de la noche (00:22, 00:25, 02:14, 02:15). **abrir ajustes no lo arreglaba.**
4. a las 03:06 se abrió la cuenta de apple y salió una alerta de icloud que, según quien usaba el ipad, pidió el código del ipad y luego el del iphone. `securityd`, 03:06:37: política de sincronización nueva (incluye la vista `Manatee`).
5. **03:06:40**: `securityd` registra `updated account trust state: TRUSTED` (`03:06:40.134`; era `UNTRUSTED` desde las 23:00, la primera línea registrada), `Manatee is available`, y `rapportd`: `Error flags changed: 0x100 < NoManatee > -> 0x0`. a las 03:06:52 el pendiente `RenewCredentials` desaparece de la lista de ajustes.
6. 03:06:45.794, en el mac: el ipad pasa de anunciar `BLE DuetSync Owner ApplePay …` a `BLE DuetSync WiFiP2P Owner ApplePay … MultiUserDevice`. sidecar conecta a las 03:10:11.
7. al reiniciar el ipad (04:07) la cuenta vuelve a `UNTRUSTED` (**04:10:37**), Manatee a `not available` (04:10:38), el bit desaparece (04:10:57, 20 s después) y sidecar falla otra vez. el pendiente `RenewCredentials` reaparece en la lista de ajustes (04:17).
8. tras poner la contraseña de la cuenta (~04:51) el bit reaparece a las 04:51:42 y sidecar conecta a las 04:52:22 por wi-fi directo (`[AWDL]`).

<p align="center"><img src="../docs/linea-de-tiempo.png" width="900" alt="línea de tiempo"></p>

<p align="center"><img src="../docs/cadena-de-causas.png" width="600" alt="cadena de causas"></p>

## el arreglo

en el ipad: **ajustes → tu nombre**, completar el aviso de la cuenta de apple (contraseña, código de verificación, código del ipad o del iphone si lo pide) y comprobar que **iCloud → contraseñas y llavero** está activado. si el aviso no sale o no basta, cerrar sesión de la cuenta y volver a entrar.

para comprobar que quedó: `./sidecar-probe status` debe decir `WiFiP2P presente` y `./sidecar-probe connect` debe decir `CONECTADO`. la prueba de fondo es reiniciar el ipad y repetirlo: si el bit sigue, quedó arreglado. **esa última prueba no la hice**: después del arreglo no reinicié el ipad.

## hipótesis descartadas

todas las que siguen se probaron y el fallo continuó. la columna de evidencia dice cómo se sabe.

| hipótesis | evidencia en contra |
|---|---|
| wi-fi, bluetooth o awdl del mac caídos | wi-fi conectado a 5 ghz desde las 17:49, bluetooth encendido, `awdl0` arriba; el mac lee `WiFiP2P` de otro dispositivo; universal control abre conexiones awdl con este mismo ipad (02:38 y 02:40) |
| compartir internet / punto de acceso en el ipad | el propio ipad registra `hostAP: NO` en cada línea |
| vpn | vpn del mac desconectadas; el usuario apagó las del ipad; sin cambio |
| banda de wi-fi (2.4 vs 5 ghz) | con el ipad en 5 ghz (mismo ssid que el mac) el bit siguió ausente: 75 de 75 lecturas por segundo |
| versiones distintas de macos e ipados | conectó (03:10) con el ipad en 27.0 y el mac en 27.2; falló (04:16) con los dos ya en 27.2 |
| cargador | conectó (03:54) con el ipad desenchufado; el 6 de sep estuvo por cable y cargando más de 20 min sin el bit |
| pantalla de actualización de software | abrirla de nuevo a las ~04:18: 75 de 75 lecturas sin el bit |
| nivel de actividad del ipad (`AcLv` de `sharingd`) | el dispositivo aparece en `User (11)` y `Screen (7)` decenas de veces (23:32 a 01:11) con `0x880102`. los identificadores están ofuscados, así que la atribución al ipad se hizo por coincidencia de banderas y de hora |
| estado viejo en el mac | reiniciar `rapportd`, `sharingd`, `SidecarRelay` e `identityservicesd`: el ipad reaparece con el mismo `0x880102`; el dato llega en vivo del ipad |
| restablecer ajustes de red del ipad (el 7 de sep) | empeoró: dejó de funcionar también el cable hasta reconstruir la confianza |
| reiniciar el ipad | no arregla: tras el reinicio la cuenta vuelve a pedir credenciales y el bit se pierde |

## dos días de trabajo, en orden

**6 y 7 de septiembre.** el error aparece con macos 27.0. se comprueba todo el lado del mac y se ve que el ipad no anuncia `WiFiP2P` (`0` veces en 6 horas). por cable funciona. un restablecimiento de ajustes de red del ipad empeora las cosas. sin causa.

**21 de septiembre.** se construye `sidecar-probe`, que lee `SidecarDevice.status` y conecta sin interfaz. se reproduce el error a voluntad. a las 03:06:45 el bit aparece por sí solo y se descubre que conecta; se pierde con el reinicio de las 04:07. se recopilan los registros del ipad por cable y en ellos está la razón exacta. se aplica el arreglo y a las 04:52 vuelve a conectar.

varias explicaciones intermedias resultaron incorrectas (nivel de actividad, banda, versiones, carga). quedan en la tabla de arriba con su refutación: lo que las tumbó fue medir, no pensar.

## límites

- **una sola pareja de equipos.** no sé si otros modelos de ipad o de mac se comportan igual.
- **no capturé los registros del ipad del momento de las 04:51.** ese instante solo está observado desde el mac (el bit) y por lo que contó quien usaba el ipad (la contraseña). el análisis del ipad cubre de las 18:44 a las 04:44.
- **no sé por qué la cuenta estaba en `RenewCredentials`.** en los registros ya venía así desde la primera hora capturada.
- **los identificadores de `sharingd` están ofuscados** y cambian al reiniciar el proceso; por eso algunas atribuciones se hicieron por coincidencia de banderas y de hora.
- los registros del 6 y 7 de septiembre ya no existen (el mac guarda unas 9-12 horas), así que esa noche solo se puede afirmar lo que quedó anotado entonces.

## para apple

- el mensaje de `-203` culpa al wi-fi cuando el motivo real es la cuenta. debería decir que hay que volver a iniciar sesión en icloud en el ipad.
- el ipad sabe por qué no anuncia el bit (lo escribe en el registro), pero el mac no tiene forma de saberlo.
- otros usuarios reportan el mismo mensaje y a veces se resuelve cerrando sesión y volviendo a entrar con el apple id y activando el llavero: [1](https://discussions.apple.com/thread/255420277), [2](https://discussions.apple.com/thread/255320248).

## datos personales

los registros originales tienen el correo de la cuenta de apple, identificadores de cuenta, udid y direcciones. los extractos de `evidence/` los enmascaran; los archivos originales no se publican.
