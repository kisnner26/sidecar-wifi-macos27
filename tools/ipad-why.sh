#!/usr/bin/env bash
# ipad-why: extrae de los registros del ipad por qué no anuncia WiFiP2P.
#
# 1. con el ipad conectado por cable y desbloqueado, recopila sus registros (pide contraseña de admin):
#      sudo log collect --device-udid <UDID> --last 10h --output /tmp/ipad.logarchive
#      sudo chown -R "$USER" /tmp/ipad.logarchive
# 2. corre (inicio y fin son opcionales; el cuarto argumento elige secciones, p. ej. "4 5"):
#      ./tools/ipad-why.sh /tmp/ipad.logarchive "2026-09-20 18:44:00" "2026-09-21 04:45:00"
#
# la salida enmascara correos, identificadores de cuenta, udid, uuid y direcciones. aun así, los registros
# originales contienen datos personales: bórralos al terminar.
set -eu

ARCHIVE="${1:?uso: ipad-why.sh <archivo.logarchive> [inicio] [fin]}"
START="${2:-$(date -v-10H '+%Y-%m-%d %H:%M:%S')}"
END="${3:-$(date '+%Y-%m-%d %H:%M:%S')}"
ONLY="${4:-1 2 3 4 5 6}"   # secciones a correr, p. ej. "4 5"
LOG=/usr/bin/log
GREP=/usr/bin/grep

clean() {
  sed -E \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<correo>/g' \
    -e 's/[0-9]{6}-[0-9]{2}-[0-9a-fA-F-]{36}/<altdsid>/g' \
    -e 's/0000[0-9]{4}-[0-9A-F]{16}/<udid>/g' \
    -e 's/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/<uuid>/g' \
    -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<mac>/g'
}

show() { "$LOG" show --archive "$ARCHIVE" --start "$START" --end "$END" --style compact --predicate "$1" 2>/dev/null; }
want() { case " $ONLY " in *" $1 "*) return 0;; *) return 1;; esac; }
stamp() { sed -E 's/^(20[0-9-]+ [0-9:.]{12}).*$/\1/'; }

if want 1; then
echo "== 1. por qué el ipad no pone el bit (sharingd) =="
echo "   cada cambio del mensaje 'WiFiP2P bit is not set, ...' (sin repeticiones consecutivas)"
show 'process == "sharingd" AND eventMessage CONTAINS "WiFiP2P bit"' \
  | $GREP -E "WiFiP2P bit" \
  | sed -E 's/^(20[0-9-]+ [0-9:.]{12}).*(WiFiP2P bit [^,]*, WiFi state: [A-Za-z ]+, hostAP: [A-Z]+, NearbyAction scan: [a-z]+, Manatee: [A-Z]+).*/\1 | \2/' \
  | awk -F' \\| ' '{ if ($2 != prev) { print; prev = $2 } }'

fi
echo
if want 2; then
echo "== 2. banderas de error de rapportd (NoManatee) =="
show 'process == "rapportd" AND eventMessage CONTAINS "Error flags changed"' \
  | $GREP -E "Error flags changed" \
  | sed -E 's/^(20[0-9-]+ [0-9:.]{12}).*Error flags changed: (.*)$/\1  \2/'

fi
echo
if want 3; then
echo "== 3. disponibilidad de Manatee (solo cambios de estado) =="
show 'eventMessage CONTAINS "Manatee State" OR eventMessage CONTAINS "Manatee is available" OR eventMessage CONTAINS "Manatee not available"' \
  | $GREP -E "Manatee (State|is available|not available)" | clean \
  | sed -E 's/^(20[0-9-]+ [0-9:.]{12}) +[A-Za-z]+ +([A-Za-z]+)\[[0-9:a-f]+\] \[[^]]*\] /\1 \2 /' | cut -c1-200 \
  | awk '{ st = ($0 ~ /is available/) ? "DISPONIBLE" : "NO DISPONIBLE"; if (st != prev) { print; prev = st } }'
fi
echo
if want 4; then
echo "== 4. confianza de la cuenta en el iPad (securityd / octagon): solo cambios de estado =="
show 'process == "securityd" AND eventMessage CONTAINS "updated account trust state"' \
  | $GREP -E "updated account trust state" \
  | sed -E 's/^(20[0-9-]+ [0-9:.]{12}).*updated account trust state: ([A-Z]+).*/\1 \2/' \
  | awk '{ if ($3 != prev) { print; prev = $3 } }'
echo
fi

if want 5; then
echo "== 5. ¿estaba pendiente «renovar credenciales»? (cada vez que Ajustes lee sus pendientes, por minuto) =="
show 'process == "Preferences" AND eventMessage CONTAINS "pendingFollowUpItems"' \
  | awk '/^20[0-9][0-9]-/ { if (ts != "") print substr(ts, 1, 16) "  " (pend ? "SÍ" : "no"); ts = $0; pend = 0; next }
         /AAFollowUpIdentifier\.RenewCredentials/ { pend = 1 }
         END { if (ts != "") print substr(ts, 1, 16) "  " (pend ? "SÍ" : "no") }' \
  | awk '{ m = $1 " " $2; if (m != cur) { if (cur != "") print cur "  RenewCredentials pendiente: " flag; cur = m; flag = "no" } if ($3 == "SÍ") flag = "SÍ" } END { if (cur != "") print cur "  RenewCredentials pendiente: " flag }'
echo
fi

if want 6; then
echo "== 6. lo que hizo el iPad justo antes de recuperar Manatee =="
show 'process == "securityd" AND eventMessage CONTAINS "New syncing policy"' \
  | awk '/^20[0-9][0-9]-/ { print substr($0, 1, 23) }' | sort -u \
  | awk 'NR == 1 { first = $0 } { n++ } END { if (n) print first "  securityd: New syncing policy (userViews: FOLLOWING, incluye la vista Manatee), y " n - 1 " veces más" }'
fi
