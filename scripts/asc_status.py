#!/usr/bin/env python3
"""Consulta el estado de distribución de la app en App Store Connect.

Responde a lo que no se ve desde el proyecto local: ¿en qué estado está la
versión?, ¿qué build es la que está publicada?, ¿en qué países?, ¿con qué precio?

Credenciales: una clave de la API de App Store Connect (Usuarios y acceso ->
Integraciones -> Claves). Se configuran en ~/.appstoreconnect/config.json:

    {"key_id": "XXXXXXXXXX", "issuer_id": "aaaa-bbbb-...", "bundle_id": "com.tuempresa.TuApp"}

y el .p8 en ~/.appstoreconnect/private_keys/AuthKey_<key_id>.p8

Los acuerdos (Acuerdos, Impuestos y Banca) NO se pueden consultar por API:
Apple no publica ningún endpoint. Hay que mirarlos en la web.
"""

import base64
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

CONFIG = Path.home() / ".appstoreconnect" / "config.json"
KEYS_DIR = Path.home() / ".appstoreconnect" / "private_keys"
API = "https://api.appstoreconnect.apple.com"

# Los estados que devuelve la API son crípticos; esto es lo que significan.
ESTADOS = {
    "READY_FOR_SALE": "publicada y a la venta",
    "PENDING_DEVELOPER_RELEASE": "APROBADA PERO SIN PUBLICAR -> hay que pulsar 'Publicar esta versión'",
    "PROCESSING_FOR_APP_STORE": "procesándose antes de salir",
    "WAITING_FOR_REVIEW": "en cola de revisión",
    "IN_REVIEW": "en revisión ahora mismo",
    "PENDING_APPLE_RELEASE": "aprobada, esperando a que Apple la publique",
    "PREPARE_FOR_SUBMISSION": "borrador, sin enviar a revisión",
    "REJECTED": "RECHAZADA por revisión",
    "METADATA_REJECTED": "RECHAZADA por los textos o capturas",
    "DEVELOPER_REMOVED_FROM_SALE": "retirada de la venta por ti",
    "REPLACED_WITH_NEW_VERSION": "sustituida por una versión posterior",
}

PUBLICACION = {
    "MANUAL": "manual (no sale hasta que lo pulses)",
    "AFTER_APPROVAL": "automática al aprobarse",
    "SCHEDULED": "programada para una fecha",
}


def load_config():
    if not CONFIG.exists():
        sys.exit(
            f"Falta {CONFIG}.\n"
            'Crea el fichero con: {"key_id": "...", "issuer_id": "...", "bundle_id": "..."}'
        )
    cfg = json.loads(CONFIG.read_text())
    for campo in ("key_id", "issuer_id", "bundle_id"):
        if not cfg.get(campo):
            sys.exit(f"Falta '{campo}' en {CONFIG}")
    key_path = KEYS_DIR / f"AuthKey_{cfg['key_id']}.p8"
    if not key_path.exists():
        sys.exit(f"No encuentro la clave privada en {key_path}")
    cfg["private_key"] = key_path.read_text()
    return cfg


def make_token(cfg):
    ahora = int(time.time())
    return jwt.encode(
        {"iss": cfg["issuer_id"], "iat": ahora, "exp": ahora + 900, "aud": "appstoreconnect-v1"},
        cfg["private_key"],
        algorithm="ES256",
        headers={"kid": cfg["key_id"], "typ": "JWT"},
    )


def get(token, path, **params):
    """GET a la API. Devuelve el JSON, o {'_error': ...} si falla.

    Los endpoints cambian de versión a menudo, así que un fallo en uno no debe
    tumbar el informe entero.
    """
    url = f"{API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        cuerpo = e.read().decode("utf-8", "replace")
        try:
            detalle = json.loads(cuerpo)["errors"][0].get("detail", cuerpo)
        except Exception:
            detalle = cuerpo[:200]
        return {"_error": f"HTTP {e.code}: {detalle}"}
    except Exception as e:  # red, timeout, DNS
        return {"_error": str(e)}


def attrs(recurso):
    return (recurso or {}).get("attributes", {}) or {}


def codigo_territorio(tid):
    """El id de un territoryAvailability es base64 de {"s":"<appId>","t":"ESP"}."""
    try:
        relleno = tid + "=" * (-len(tid) % 4)
        return json.loads(base64.b64decode(relleno))["t"]
    except Exception:
        return tid[:12]


def informe_versiones(token, app_id):
    print("== Versiones ==")
    versiones = get(token, f"/v1/apps/{app_id}/appStoreVersions", limit=5)
    if "_error" in versiones:
        print(f"  (no disponible: {versiones['_error']})")
        return
    for v in versiones.get("data", []):
        va = attrs(v)
        estado = va.get("appStoreState") or va.get("state") or "?"
        tipo = va.get("releaseType", "?")
        print(f"  Versión {va.get('versionString', '?')}")
        print(f"    estado:      {ESTADOS.get(estado, estado)}")
        print(f"    publicación: {PUBLICACION.get(tipo, tipo)}")
        if va.get("earliestReleaseDate"):
            print(f"    fecha programada: {va['earliestReleaseDate']}")

        build = get(token, f"/v1/appStoreVersions/{v['id']}/build")
        if "_error" not in build and build.get("data"):
            ba = attrs(build["data"])
            print(f"    build publicada: {ba.get('version', '?')} (subida {ba.get('uploadedDate', '?')[:10]})")
    print()


def informe_builds(token, app_id):
    print("== Builds subidas ==")
    builds = get(token, f"/v1/apps/{app_id}/builds", limit=5)
    if "_error" in builds:
        print(f"  (no disponible: {builds['_error']})")
        print()
        return
    for b in builds.get("data", []):
        ba = attrs(b)
        caduca = ba.get("expirationDate", "")[:10]
        estado = "caducada" if ba.get("expired") else f"caduca {caduca}"
        print(f"  build {ba.get('version', '?'):4} {ba.get('processingState', '?'):8} {estado}")
    print()


def informe_territorios(token, app_id):
    print("== Disponibilidad ==")
    disp = get(token, f"/v2/appAvailabilities/{app_id}/territoryAvailabilities", limit=200)
    if "_error" in disp:
        print(f"  (no disponible por API: {disp['_error']})")
        print("  Compruébalo en la pestaña 'Precios y disponibilidad'.")
        print()
        return
    datos = disp.get("data", [])
    disponibles = {codigo_territorio(t["id"]) for t in datos if attrs(t).get("available")}
    preorden = [codigo_territorio(t["id"]) for t in datos if attrs(t).get("preOrderEnabled")]
    print(f"  Disponible en {len(disponibles)} de {len(datos)} territorios")
    print(f"  España: {'sí' if 'ESP' in disponibles else 'NO  <-- revísalo'}")
    if preorden:
        print(f"  Con pedido anticipado activo: {', '.join(preorden)}  <-- revísalo")
    fechas = {attrs(t).get("releaseDate") for t in datos if attrs(t).get("available")}
    fechas.discard(None)
    if fechas:
        print(f"  Fecha de publicación: {', '.join(sorted(fechas))}")
    print()


def informe_precio(token, app_id):
    print("== Precio ==")
    precio = get(token, f"/v1/apps/{app_id}/appPriceSchedule", include="manualPrices")
    if "_error" in precio:
        print(f"  (no disponible por API: {precio['_error']})")
        print("  Compruébalo en la pestaña 'Precios y disponibilidad'.")
    else:
        print(f"  Programación de precios: {'configurada' if precio.get('data') else 'SIN CONFIGURAR  <-- revísalo'}")
    print()


def main():
    cfg = load_config()
    token = make_token(cfg)

    apps = get(token, "/v1/apps", **{"filter[bundleId]": cfg["bundle_id"]})
    if "_error" in apps:
        sys.exit(f"No he podido consultar la API: {apps['_error']}")
    if not apps.get("data"):
        sys.exit(f"No hay ninguna app con bundle id {cfg['bundle_id']} en esta cuenta.")

    app = apps["data"][0]
    app_id = app["id"]
    a = attrs(app)
    print(f"App: {a.get('name')}  ({a.get('bundleId')})")
    print(f"     SKU {a.get('sku')} · Apple ID {app_id}")
    print(f"     https://apps.apple.com/es/app/id{app_id}")
    print()

    informe_versiones(token, app_id)
    informe_builds(token, app_id)
    informe_territorios(token, app_id)
    informe_precio(token, app_id)

    print("== Lo que la API no puede decirte ==")
    print("  Acuerdos, Impuestos y Banca: no hay endpoint público.")
    print("  Míralo en https://appstoreconnect.apple.com/business")


if __name__ == "__main__":
    main()
