// sidecar-probe: lee y prueba sidecar desde la terminal, sin tocar la interfaz.
// usa la api privada SidecarCore (la misma que el menú de pantalla), solo para diagnóstico.
//
//   swiftc -O tools/sidecar-probe.swift -o sidecar-probe
//   ./sidecar-probe status     estado que sidecar tiene del ipad, y si anuncia WiFiP2P
//   ./sidecar-probe watch      vigila el bit y avisa en cada cambio (ctrl+c para salir)
//   ./sidecar-probe connect    intenta conectar y muestra el error exacto
//   ./sidecar-probe list       dispositivos que sidecar ve y los conectados
//
// el "status" de SidecarDevice es una máscara de banderas de rapport. la que importa es 0x200 (WiFiP2P):
// sin ella, SidecarRelay aborta con SidecarErrorDomain -203 antes de intentar ninguna conexión inalámbrica.
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let wifiP2P = 0x200

guard dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_NOW) != nil,
    let managerClass = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
    let managerRef = managerClass.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue()
else {
    print("no pude cargar SidecarCore: ¿macos 13 o superior?")
    exit(2)
}
let manager = managerRef as AnyObject

func devices(_ selector: String) -> [AnyObject] {
    (manager.perform(NSSelectorFromString(selector))?.takeUnretainedValue() as? [AnyObject]) ?? []
}

func describe(_ device: AnyObject) -> String {
    let name = device.value(forKey: "name") as? String ?? "?"
    let model = device.value(forKey: "model") as? String ?? "?"
    let status = device.value(forKey: "status") as? Int ?? 0
    let p2p = status & wifiP2P != 0
    return String(format: "%@ (%@)  status 0x%X  %@", name, model, status, p2p ? "WiFiP2P presente" : "SIN WiFiP2P")
}

func stamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

switch CommandLine.arguments.dropFirst().first ?? "status" {
case "list":
    let all = devices("devices"), connected = devices("connectedDevices")
    print("dispositivos: \(all.count)")
    all.forEach { print(" -", describe($0)) }
    print("conectados: \(connected.count)")

case "status":
    guard let device = devices("devices").first else { print("sidecar no ve ningún dispositivo"); exit(1) }
    print(describe(device))
    exit((device.value(forKey: "status") as? Int ?? 0) & wifiP2P != 0 ? 0 : 3)

case "watch":
    var last = -2
    print(stamp(), "vigilando el bit 0x200 (WiFiP2P). ctrl+c para salir")
    while true {
        let status = (devices("devices").first?.value(forKey: "status") as? Int) ?? -1
        if status != last {
            if status < 0 { print(stamp(), "el dispositivo no aparece") }
            else { print(stamp(), String(format: "status 0x%X", status), status & wifiP2P != 0 ? "-> WiFiP2P PRESENTE" : "-> sin WiFiP2P") }
            last = status
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
    }

case "connect":
    guard let device = devices("devices").first else { print("sidecar no ve ningún dispositivo"); exit(1) }
    print(stamp(), "conectando con:", device.value(forKey: "name") ?? "?")
    var finished = false
    var failed = false
    let completion: @convention(block) (NSError?) -> Void = { error in
        if let error {
            print(stamp(), "FALLO:", error.domain, error.code, error.localizedDescription)
            failed = true
        } else {
            print(stamp(), "CONECTADO")
        }
        finished = true
    }
    _ = manager.perform(NSSelectorFromString("connectToDevice:completion:"), with: device, with: completion as AnyObject)
    let limit = Date().addingTimeInterval(40)
    while !finished && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    if !finished { print("sin respuesta en 40 s") }
    exit(finished && !failed ? 0 : 1)

default:
    print("uso: sidecar-probe status | watch | connect | list")
    exit(64)
}
