# cómo decide sidecar si conecta por wi-fi

lo que sigue sale de leer los registros y los binarios de macos 27.2 (`26B5086k`) y del propio ipad (ipados 27). es ingeniería inversa de diagnóstico sobre un equipo propio: sin parchear nada, sin desactivar sip y sin modificar ningún proceso de apple.

## la regla, medida

`SidecarDevice` (clase de la api privada `SidecarCore`) tiene una propiedad `status`: una máscara con las banderas que el ipad anuncia por bluetooth (rapport). el mismo número aparece en `sharingd` como `SF 0x…` y en `SidecarRelay` como `Device Changed <…>`.

| `status` | banderas | sidecar por wi-fi |
|---|---|---|
| `0x880102` | `BLE DuetSync Owner ApplePay` | falla, `-203` |
| `0x880302` | `BLE DuetSync WiFiP2P Owner ApplePay` | conecta |

la diferencia es un solo bit, **`0x200` = `WiFiP2P`**. las otras banderas se deducen por el orden de los nombres.

por cable no hace falta el bit: el ipad anuncia `iWiFi … USB` y la conexión va por usb.

## dónde nace el `-203`

- proceso: `/usr/libexec/SidecarRelay` (agente de lanzamiento `com.apple.sidecar-relay`), escrito en swift, `arm64e`.
- cadenas relevantes que contiene: `RapportStatusFlags`, `WiFiP2P`, `WiFiOff`, `WiFiHostAP`, `iWiFi`, `NoUSB`, `ForceAWDL`, `ForceUSB`, `SidecarTransport`.
- una sola instrucción carga el código `-203`: `mov x2, #-0xcb` en `0x100046908` (build `26B5086k`).
- se llega ahí por `tbz w22, #0x0, 0x100046900` desde un bloque que compara las banderas del dispositivo contra unas máscaras (`and` + `cmp`/`ccmp`) y, si no se cumplen, evalúa un `String.hasPrefix` para elegir entre dos errores. no decodifiqué el significado exacto de cada máscara: las conclusiones sobre qué bit importa vienen de la medición de arriba, no de esa lectura.
- en los registros, la decisión tarda **25 ms** (`Connecting to IDS … 'com.apple.sidecar.display'` → `Open Session Failed … (-203)`), imposible si hubiera intentado abrir una conexión de red. es una comprobación local.

el texto del diálogo («Wi‑Fi is not available on the device… not in use for Personal Hotspot») es genérico: se muestra para cualquier `-203`, sea cual sea el motivo real.

## cómo se enciende el wi-fi directo (awdl)

el wi-fi directo entre dos equipos no está siempre encendido. `rapportd` lo maneja bajo demanda:

- un dispositivo manda un evento **NeedsAWDL** por bluetooth; ambos abren una «transacción de wi-fi p2p» (`RPWiFiP2PTransaction`) con una lista de clientes registrados, y la cierran cuando nadie la necesita.
- se ve en los registros con universal control (`Ensemble`): `Received NeedsAWDL enable event` → `WiFi P2P transaction enabled for client 'Ensemble'` → un minuto después `invalidate` / `disabled`.
- `rapportd` contiene además la cadena `Ignoring NeedsAWDL device that does not have expected status flags`: las banderas de estado también gobiernan si el mac siquiera intenta abrir el canal.

por eso universal control puede usar el canal con el ipad aunque el ipad no anuncie `WiFiP2P`: usa un camino forzado (`ForceAWDL`). sidecar no.

## qué decide el ipad

en el ipad, `sharingd` (`SDNearbyAgentCore`) escribe la razón cada ~100 ms mientras no pone el bit:

```
WiFiP2P bit is not set, WiFi state: Connected, hostAP: NO, NearbyAction scan: on, Manatee: NO
```

las cuatro entradas de la decisión son: estado del wi-fi, si el equipo es punto de acceso, si el escaneo de acciones cercanas está activo y si **manatee** está disponible. en toda la captura solo cambió la última mientras el wi-fi estaba conectado:

| situación | `WiFi state` | `hostAP` | `scan` | `Manatee` | bit |
|---|---|---|---|---|---|
| durante horas | `Connected` | `NO` | `on` | **`NO`** | no |
| 03:06:45 a 04:07 | `Connected` | `NO` | `on` | disponible | **sí** |
| tras el reinicio | `Connected` | `NO` | `on` | **`NO`** | no |

(en los primeros segundos tras el arranque aparece `WiFi state: Unknown` con `Manatee: YES`; el bit sigue sin ponerse porque el wi-fi aún no está conectado.)

## qué es manatee y por qué falla

- manatee es la capa de cifrado de extremo a extremo del llavero de icloud y de los datos protegidos. depende de que el equipo sea de confianza en la cuenta («círculo de confianza», octagon).
- `cdpd`/`CoreCDP` (`CDPManateeStateController`) lo consulta y, mientras falla, responde: `Manatee not available due to circle failure with error: CDPStateError Code=-5403`.
- `securityd` registra la causa de fondo: `trust status: (excluded)` y `updated account trust state: UNTRUSTED` (desde las 23:00, la primera línea registrada). el estado pasa a `TRUSTED` a las 03:06:40.134, el mismo segundo en que manatee queda disponible, y vuelve a `UNTRUSTED` a las 04:10:37, tras el reinicio.
- `rapportd` lo convierte en la bandera de error `0x100 < NoManatee >`, que se ve en sus registros.
- el indicador visible es el pendiente de seguimiento de ajustes `com.apple.AAFollowUpIdentifier.RenewCredentials` («renovar credenciales»): estuvo en la lista mientras el estado era `UNTRUSTED`, desapareció al pasar a `TRUSTED` y volvió tras el reinicio del ipad. abrir ajustes sin completar la alerta no lo quita.

al completar el aviso, `securityd` recibe una política de sincronización nueva (`New syncing policy … userViews: FOLLOWING`, con `Manatee` entre las vistas), 3 s después `Manatee is available` y 5 s después el bit sale a la señal.

## api privada usada para medir

`SidecarCore` expone `SidecarDisplayManager` con `sharedManager`, `devices`, `connectedDevices`, `connectToDevice:completion:`, `connectToDevice:withConfig:completion:` y `disconnectFromDevice:completion:`. `tools/sidecar-probe.swift` la usa para leer `status` y conectar sin pasar por la interfaz. es la misma llamada del menú de pantalla (`-[SidecarDisplayManager connectToDevice:withConfig:completion:]` aparece en los registros).

## lo que no sé

- por qué la cuenta del ipad estaba en `RenewCredentials`. la primera vez que aparece `Manatee not available` en los registros es la primera hora capturada (18:46 del 20 de septiembre), así que ya venía así de antes.
- por qué se vuelve a perder tras un reinicio aun con el mismo aviso resuelto una vez. lo que sí se ve es que tras completar el aviso por segunda vez (con la contraseña) el bit volvió y siguió.
- si otros bits distintos de manatee pueden apagar `WiFiP2P`: solo se observó manatee, que es lo único que cambió mientras el resto de entradas era constante.
