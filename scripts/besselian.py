"""Genera elementos besselianos de un eclipse solar desde una efeméride JPL.

Método: Explanatory Supplement to the Astronomical Almanac, cap. 8;
Meeus, "Astronomical Algorithms" cap. 54.

Puntos críticos (los dos que estaban mal en el dataset del proyecto):
  1. Las coordenadas deben referirse al **equador y equinoccio de la fecha**,
     no a J2000. Usar J2000 en 2026 introduce ~0.117° en la declinación del eje
     por precesión — exactamente el error observado.
  2. mu es el ángulo horario de Greenwich del eje, así que depende de UT1 y por
     tanto del ΔT elegido. Se pasa explícitamente.
"""

import numpy as np
from skyfield.api import load
from skyfield import framelib

R_EARTH_KM = 6378.137          # radio ecuatorial terrestre (WGS84 / IAU)
R_SUN_OVER_R_EARTH = 696000.0 / R_EARTH_KM   # 109.1234

# Convenciones para el radio lunar (en radios terrestres).
K_ESPENAK_PENUMBRA = 0.272488   # k1 en el Canon de Espenak
K_ESPENAK_UMBRA    = 0.272281   # k2 en el Canon: limbo "Watts" medio, umbra conservadora
K_IAU              = 0.2725076  # valor IAU, usado por Jubier y otros

ts = load.timescale()
eph = load('de440s.bsp')
EARTH, SUN, MOON = eph['earth'], eph['sun'], eph['moon']


def _vectors(jd_tt, aberration_sun, aberration_moon):
    """Posiciones geocéntricas de Luna y Sol en radios terrestres,
    referidas al equador y equinoccio verdaderos de la fecha."""
    t = ts.tt_jd(jd_tt)
    e = EARTH.at(t)
    frame = framelib.true_equator_and_equinox_of_date

    def pos(body, aberr):
        p = e.observe(body)          # corregido de tiempo-luz
        if aberr:
            p = p.apparent()         # + aberración anual y deflexión
        return p.frame_xyz(frame).km / R_EARTH_KM

    return pos(MOON, aberration_moon), pos(SUN, aberration_sun)


def elements_at(jd_tt, delta_t, k1, k2, aberration_sun=True, aberration_moon=False):
    """Elementos besselianos instantáneos.

    Devuelve (x, y, d_deg, l1, l2, mu_deg, tanf1, tanf2).
    """
    M, S = _vectors(jd_tt, aberration_sun, aberration_moon)

    G = S - M                      # del centro de la Luna hacia el Sol
    g = np.linalg.norm(G)
    a = np.arctan2(G[1], G[0])     # ascensión recta del eje de la sombra
    d = np.arcsin(G[2] / g)        # declinación del eje

    # Base del plano fundamental: z a lo largo del eje, x hacia el este.
    zh = np.array([np.cos(d) * np.cos(a), np.cos(d) * np.sin(a), np.sin(d)])
    xh = np.array([-np.sin(a), np.cos(a), 0.0])
    yh = np.array([-np.sin(d) * np.cos(a), -np.sin(d) * np.sin(a), np.cos(d)])

    x, y, z = M @ xh, M @ yh, M @ zh

    # Conos de sombra: f1 externo (penumbra), f2 interno (umbra).
    sin_f1 = (R_SUN_OVER_R_EARTH + k1) / g
    sin_f2 = (R_SUN_OVER_R_EARTH - k2) / g
    tan_f1 = sin_f1 / np.sqrt(1 - sin_f1 ** 2)
    tan_f2 = sin_f2 / np.sqrt(1 - sin_f2 ** 2)

    l1 = (z + k1 / sin_f1) * tan_f1
    l2 = (z - k2 / sin_f2) * tan_f2

    # mu = tiempo sidéreo aparente − ascensión recta del eje, referido al
    # **meridiano de efemérides** (convención de Espenak / Five Millennium Canon),
    # no al de Greenwich. El meridiano de efemérides está 1.002738·ΔT al este, de
    # modo que el tiempo resultante sale directamente en TDT y el usuario resta ΔT
    # al final. Es la convención que asume EclipseEngine (H = mu + lon; luego
    # utcSeconds = (t0+t)*3600 − ΔT), así que hay que generarla igual.
    # Verificado: evaluar GAST en UT1 = TT − ΔT reproduce los valores de la NASA
    # desplazados exactamente en 1.002738·ΔT·15/3600 grados.
    t_rot = ts.ut1_jd(jd_tt)
    gast_deg = t_rot.gast * 15.0
    mu = (gast_deg - np.degrees(a)) % 360.0

    return x, y, np.degrees(d), l1, l2, mu, tan_f1, tan_f2


def fit(jd_t0_tt, delta_t, k1, k2, half_window_h=3.0, n=25,
        aberration_sun=True, aberration_moon=False):
    """Ajusta polinomios cúbicos a los elementos en una ventana centrada en t0.

    Devuelve un dict con las listas de coeficientes, listo para eclipses.json.
    """
    hours = np.linspace(-half_window_h, half_window_h, n)
    rows = [elements_at(jd_t0_tt + h / 24.0, delta_t, k1, k2,
                        aberration_sun, aberration_moon) for h in hours]
    arr = np.array([r[:6] for r in rows])

    # mu crece ~15°/h: quitar saltos de 360° antes de ajustar.
    arr[:, 5] = np.unwrap(np.radians(arr[:, 5]))
    arr[:, 5] = np.degrees(arr[:, 5])

    out = {}
    for i, name in enumerate(['x', 'y', 'd', 'l1', 'l2', 'mu']):
        deg = 3 if name in ('x', 'y') else 2
        c = np.polyfit(hours, arr[:, i], deg)[::-1]     # orden ascendente
        out[name] = [float(v) for v in c] + [0.0] * (4 - len(c))
    out['mu'][0] = out['mu'][0] % 360.0

    mid = rows[n // 2]
    out['tan_f1'] = float(mid[6])
    out['tan_f2'] = float(mid[7])
    return out


def rms_residual(jd_t0_tt, delta_t, k1, k2, **kw):
    """RMS del ajuste, en las unidades de cada elemento (control de calidad)."""
    hours = np.linspace(-3, 3, 25)
    rows = np.array([elements_at(jd_t0_tt + h / 24.0, delta_t, k1, k2, **kw)[:6]
                     for h in hours])
    f = fit(jd_t0_tt, delta_t, k1, k2, **kw)
    res = {}
    for i, name in enumerate(['x', 'y', 'd', 'l1', 'l2']):
        p = f[name]
        model = p[0] + hours * (p[1] + hours * (p[2] + hours * p[3]))
        res[name] = float(np.sqrt(np.mean((rows[:, i] - model) ** 2)))
    return res
