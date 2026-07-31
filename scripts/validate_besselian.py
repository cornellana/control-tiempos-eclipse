#!/usr/bin/env python3
"""Valida el generador de elementos besselianos contra los valores publicados
por NASA/Espenak, y emite el bloque JSON de un eclipse para eclipses.json.

Uso:
    python3 -m venv .venv && .venv/bin/pip install skyfield
    .venv/bin/python scripts/validate_besselian.py --validate
    .venv/bin/python scripts/validate_besselian.py --emit 2026-08-12

Por qué existe este script
--------------------------
El bloque de SE2026Aug12T de eclipses.json se generó en su día con las
coordenadas referidas a **J2000** en lugar de al equador y equinoccio **de la
fecha**. En 2026 la precesión desde J2000 vale 0.1168° en declinación, y ese es
exactamente el error que tenía d[0] (14.91342 en vez de 14.79667). El efecto
sobre la app: los contactos C2/C3 salían 5–7 s antes de tiempo y la franja de
totalidad quedaba desplazada ~10 km al norte.

Convenciones (deben coincidir con EclipseEngine.swift)
------------------------------------------------------
* Coordenadas: equador y equinoccio verdaderos de la fecha, posiciones
  aparentes (tiempo-luz + aberración + deflexión) de Sol y Luna.
* mu referido al **meridiano de efemérides** (convención de Espenak), no al de
  Greenwich: el motor hace H = mu + lon y luego UTC = TDT − ΔT.
* Radio lunar: k = 0.2725076 (IAU). Espenak usa k2 = 0.272281 para la umbra,
  lo que estrecha la franja ~3 km. En un punto a pocos km del límite la
  convención decide el resultado — ver la nota del README.

Validación esperada (DE440s frente a NASA/Espenak, VSOP87/ELP2000-85):
    d      < 0.1 arcsec
    x, y   < 1 km
    l1, l2 < 0.1 km
    mu     < 0.2 arcsec
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from besselian import (ts, fit, K_ESPENAK_PENUMBRA, K_ESPENAK_UMBRA, K_IAU)

# Elementos publicados en eclipse.gsfc.nasa.gov/SEbeselm/, para autocomprobación.
NASA_REFERENCE = {
    "2027-08-02": dict(
        t0=(2027, 8, 2, 10), delta_t=76.0,
        x=-0.019645, y=0.160063, d=17.76247,
        l1=0.530596, l2=-0.015464, mu=328.42249),
    "2026-08-12": dict(
        t0=(2026, 8, 12, 18), delta_t=71.4,
        x=0.475593, y=0.771161, d=14.79667,
        l1=0.537954, l2=-0.008142, mu=88.74776),
}

R_EARTH_KM = 6378.137

# Tolerancias de aceptación de la validación.
TOL = {"x": 2.0, "y": 2.0, "l1": 0.5, "l2": 0.5,   # km
       "d": 0.5, "mu": 1.0}                         # arcsec


def validate() -> bool:
    """Comprueba que el generador reproduce los elementos de la NASA."""
    ok = True
    for fecha, ref in NASA_REFERENCE.items():
        y, m, d, h = ref["t0"]
        jd = ts.tt(y, m, d, h, 0, 0).tt
        got = fit(jd, ref["delta_t"], K_ESPENAK_PENUMBRA, K_ESPENAK_UMBRA,
                  aberration_sun=True, aberration_moon=True)
        print(f"\n{fecha}  (DE440s frente a NASA/Espenak)")
        for name in ("x", "y", "d", "l1", "l2", "mu"):
            diff = got[name][0] - ref[name]
            if name in ("d", "mu"):
                val, unit = diff * 3600.0, "arcsec"
            else:
                val, unit = diff * R_EARTH_KM, "km"
            passed = abs(val) <= TOL[name]
            ok &= passed
            print(f"   {name:3} {got[name][0]:>13.6f}  dif {val:>+9.3f} {unit:<7}"
                  f" {'OK' if passed else 'FALLA'}")
    return ok


def emit(fecha: str, delta_t: float, k_iau: bool) -> None:
    """Imprime el bloque JSON de elementos para esa fecha."""
    y, m, d = (int(v) for v in fecha.split("-"))
    # t0 se fija a la hora entera más próxima al máximo del eclipse.
    ref = NASA_REFERENCE.get(fecha)
    hour = ref["t0"][3] if ref else 12
    jd = ts.tt(y, m, d, hour, 0, 0).tt
    k1, k2 = (K_IAU, K_IAU) if k_iau else (K_ESPENAK_PENUMBRA, K_ESPENAK_UMBRA)
    f = fit(jd, delta_t, k1, k2, aberration_sun=True, aberration_moon=True)
    block = {name: [round(v, 9) for v in f[name]]
             for name in ("x", "y", "d", "l1", "l2", "mu")}
    block["tan_f1"] = round(f["tan_f1"], 8)
    block["tan_f2"] = round(f["tan_f2"], 8)
    block["t0_tdt_hours"] = float(hour)
    block["delta_t_seconds"] = delta_t
    block["ephemeris_note"] = (
        f"DE440s (JPL) via Skyfield. Equador y equinoccio verdaderos de la fecha; "
        f"posiciones aparentes. mu en el meridiano de efemerides (Espenak). "
        f"k1={k1}, k2={k2}. Ajuste cubico 25 puntos sobre +/-3 h. "
        f"Generado por scripts/validate_besselian.py.")
    print(json.dumps(block, indent=1, ensure_ascii=False))


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--validate", action="store_true",
                   help="comprueba el generador contra los valores de la NASA")
    p.add_argument("--emit", metavar="YYYY-MM-DD",
                   help="emite el bloque JSON de elementos de esa fecha")
    p.add_argument("--delta-t", type=float, default=69.1,
                   help="ΔT en segundos (por defecto 69.1, valor de Jubier para 2026)")
    p.add_argument("--espenak-k", action="store_true",
                   help="usa k2=0.272281 (Espenak) en vez de k=0.2725076 (IAU)")
    a = p.parse_args()

    if a.validate:
        ok = validate()
        print("\nRESULTADO:", "validación superada" if ok else "VALIDACIÓN FALLIDA")
        return 0 if ok else 1
    if a.emit:
        emit(a.emit, a.delta_t, not a.espenak_k)
        return 0
    p.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
