#!/usr/bin/env python3
"""Genera el Reel vertical de Control Tiempos Eclipse.

Salida: frames PNG 1080x1920 a 30 fps que luego ensambla ffmpeg.
El audio son los avisos hablados reales, sintetizados con la misma voz
en-GB que usa la app.

Uso:  python3 make_reel.py [es|en]
"""

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

AQUI = Path(__file__).parent
SUFIJO = ""   # "_es" para las capturas de la app en castellano
W, H = 1080, 1920
FPS = 30

ORO       = (208, 166, 88)
ORO_CLARO = (240, 214, 160)
FONDO     = (8, 8, 10)
BLANCO    = (245, 245, 247)


# --------------------------------------------------------------------------
# Tipografía
# --------------------------------------------------------------------------

# Índices verificados de HelveticaNeue.ttc: 0 Regular, 1 Bold, 9 Condensed Black.
CANDIDATAS_NEGRA = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 9),
    ("/System/Library/Fonts/Avenir Next Condensed.ttc", 8),
    ("/System/Library/Fonts/Helvetica.ttc", 1),
]
CANDIDATAS_BOLD = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 1),
    ("/System/Library/Fonts/Helvetica.ttc", 1),
    ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0),
]
CANDIDATAS_REG = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 0),
    ("/System/Library/Fonts/Helvetica.ttc", 0),
    ("/System/Library/Fonts/SFNS.ttf", 0),
]


def _cargar(candidatas, size):
    for ruta, idx in candidatas:
        try:
            return ImageFont.truetype(ruta, size, index=idx)
        except Exception:
            continue
    return ImageFont.load_default()


def negra(size):
    """Condensed Black — para los titulares que tienen que parar el scroll."""
    return _cargar(CANDIDATAS_NEGRA, size)


def bold(size):
    return _cargar(CANDIDATAS_BOLD, size)


def regular(size):
    return _cargar(CANDIDATAS_REG, size)


def negra_ajustada(draw, lineas, size, ancho_max=W - 110):
    """Elige el mayor cuerpo que quepa a lo ancho.

    El mismo rótulo ocupa distinto en cada idioma ("80 SECONDS" frente a
    "80 SEGUNDOS"), así que fijar el cuerpo a ojo desborda en cuanto se traduce.
    """
    while size > 24:
        f = negra(size)
        if max(draw.textlength(l, font=f) for l in lineas) <= ancho_max:
            return f
        size -= 4
    return negra(size)


def texto(draw, xy, s, font, fill, anchor="mm", tracking=0, alpha=255):
    """Dibuja texto con tracking (espaciado entre letras) opcional."""
    if alpha <= 0:
        return
    color = fill if len(fill) == 4 else (*fill, int(alpha))
    if tracking == 0:
        draw.text(xy, s, font=font, fill=color, anchor=anchor)
        return
    ancho = sum(draw.textlength(c, font=font) for c in s) + tracking * (len(s) - 1)
    x, y = xy
    if anchor[0] == "m":
        x -= ancho / 2
    elif anchor[0] == "r":
        x -= ancho
    for c in s:
        draw.text((x, y), c, font=font, fill=color, anchor="l" + anchor[1])
        x += draw.textlength(c, font=font) + tracking


def multilinea(draw, cx, cy, lineas, font, fill, interlineado=1.18, tracking=0, alpha=255):
    alto = font.size * interlineado
    y = cy - alto * (len(lineas) - 1) / 2
    for l in lineas:
        texto(draw, (cx, y), l, font, fill, tracking=tracking, alpha=alpha)
        y += alto


# --------------------------------------------------------------------------
# Utilidades de animación
# --------------------------------------------------------------------------

def suave(t):
    """Ease in-out cúbico, t en [0,1]."""
    t = max(0.0, min(1.0, t))
    return 3 * t * t - 2 * t * t * t


def rampa(t, ini, fin):
    """0 antes de ini, 1 después de fin, suavizado entre medias."""
    if fin <= ini:
        return 1.0 if t >= fin else 0.0
    return suave((t - ini) / (fin - ini))


def aparecer(t, ini, dur_in=0.35, vis=1.0, dur_out=0.35):
    """Curva de opacidad para un elemento que entra, se queda y sale."""
    if t < ini:
        return 0.0
    if t < ini + dur_in:
        return suave((t - ini) / dur_in)
    if t < ini + dur_in + vis:
        return 1.0
    if t < ini + dur_in + vis + dur_out:
        return 1.0 - suave((t - ini - dur_in - vis) / dur_out)
    return 0.0


# --------------------------------------------------------------------------
# Corona solar
# --------------------------------------------------------------------------

_corona_cache = {}


def corona(radio, escala, semilla=0):
    """Corona solar: disco negro con halo dorado que decae exponencialmente."""
    clave = (radio, escala)
    if clave in _corona_cache:
        return _corona_cache[clave]

    lado = int(radio * 7)
    ys, xs = np.mgrid[0:lado, 0:lado]
    cx = cy = lado / 2
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)

    # Halo: decae con la distancia al limbo. Tres escalas — la más larga da esa
    # extensión tenue que tiene la corona real y que un degradado corto no imita.
    halo = (np.exp(-(d - radio) / escala) * 0.70
            + np.exp(-(d - radio) / (escala * 3.0)) * 0.30
            + np.exp(-(d - radio) / (escala * 9.0)) * 0.12)
    halo[d < radio] = 0.0

    # Estructura angular muy leve. Con amplitudes altas parece un sol de dibujos,
    # así que se combinan frecuencias primas con poco peso para romper la simetría.
    ang = np.arctan2(ys - cy, xs - cx)
    rayos = (1.0
             + 0.07 * np.sin(ang * 7 + semilla)
             + 0.05 * np.sin(ang * 13 - semilla * 2)
             + 0.04 * np.sin(ang * 23 + 1.7))
    halo *= np.clip(rayos, 0.85, 1.15)

    # Anillo fino justo en el limbo.
    limbo = np.exp(-((d - radio) ** 2) / (2 * (radio * 0.028) ** 2))
    halo += limbo * 0.95

    halo = np.clip(halo, 0, 1.5)

    img = np.zeros((lado, lado, 4), dtype=np.uint8)
    for i, c in enumerate(ORO_CLARO):
        img[:, :, i] = np.clip(halo * c, 0, 255).astype(np.uint8)
    img[:, :, 3] = np.clip(halo * 255, 0, 255).astype(np.uint8)

    out = Image.fromarray(img, "RGBA").filter(ImageFilter.GaussianBlur(radio * 0.05))
    _corona_cache[clave] = out
    return out


# --------------------------------------------------------------------------
# Pantallas de la app
# --------------------------------------------------------------------------

def pantalla(nombre, alto_destino):
    """Carga una captura del simulador y la deja con esquinas redondeadas."""
    im = Image.open(AQUI / f"{nombre}.png").convert("RGB")
    ratio = alto_destino / im.height
    im = im.resize((int(im.width * ratio), alto_destino), Image.LANCZOS)

    radio = int(im.width * 0.085)
    mascara = Image.new("L", im.size, 0)
    ImageDraw.Draw(mascara).rounded_rectangle([0, 0, im.width - 1, im.height - 1],
                                              radius=radio, fill=255)
    out = Image.new("RGBA", im.size)
    out.paste(im, (0, 0))
    out.putalpha(mascara)
    return out


def recorte(nombre, caja, ancho_destino):
    """Recorta una zona de una captura y la escala.

    `caja` va en fracciones (x0, y0, x1, y1) del original. Mostrar la pantalla
    entera deja los tiempos ilegibles en un móvil, así que en las escenas de
    prueba se enseña solo la tarjeta, a tamaño grande.
    """
    im = Image.open(AQUI / f"{nombre}.png").convert("RGB")
    x0, y0, x1, y1 = caja
    im = im.crop((int(x0 * im.width), int(y0 * im.height),
                  int(x1 * im.width), int(y1 * im.height)))
    ratio = ancho_destino / im.width
    im = im.resize((ancho_destino, int(im.height * ratio)), Image.LANCZOS)

    radio = 34
    mascara = Image.new("L", im.size, 0)
    ImageDraw.Draw(mascara).rounded_rectangle([0, 0, im.width - 1, im.height - 1],
                                              radius=radio, fill=255)
    out = Image.new("RGBA", im.size)
    out.paste(im, (0, 0))
    out.putalpha(mascara)
    return out


def pegar_con_brillo(base, sprite, cx, cy, alpha):
    if alpha <= 0.01:
        return
    x = int(cx - sprite.width / 2)
    y = int(cy - sprite.height / 2)

    # Halo dorado difuso detrás del móvil.
    glow = Image.new("RGBA", (sprite.width + 120, sprite.height + 120), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(
        [60, 60, glow.width - 60, glow.height - 60],
        radius=int(sprite.width * 0.085), fill=(*ORO, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(45))
    _componer(base, glow, x - 60, y - 60, alpha * 0.9)
    _componer(base, sprite, x, y, alpha)


def _componer(base, sprite, x, y, alpha):
    if alpha <= 0.01:
        return
    if alpha < 0.999:
        sprite = sprite.copy()
        a = sprite.getchannel("A").point(lambda v: int(v * alpha))
        sprite.putalpha(a)
    base.alpha_composite(sprite, (int(x), int(y)))


# --------------------------------------------------------------------------
# Guion
# --------------------------------------------------------------------------

GUION = {
    "en": {
        "fecha":    "12 AUGUST 2026",
        "hook1":    ["80 SECONDS"],
        "hook2":    ["OF TOTAL", "DARKNESS"],
        "problema": ["YOUR EYES BELONG", "ON THE SKY."],
        "problema2": ["NOT ON A SCREEN."],
        "voz_tit":  "SO THE APP TALKS TO YOU",
        "cues": [
            (7.00, 8.78, "One minute to first contact."),
            (9.40, 11.69, "Contact. The eclipse has begun."),
            (12.20, 14.22, "Totality. Remove the filter."),
            (14.90, 15.34, "Shoot."),
        ],
        "proof1":   ["EXACT CONTACT TIMES.", "COMPUTED OFFLINE."],
        "proof2":   ["EVERY CUE SPOKEN", "ON THE SECOND."],
        "cta_tit":  "ECLIPSE TIMER",
        "cta_sub":  "Free on the App Store",
        "cta_pie":  "Search:  Control Tiempos Eclipse",
        "cta_link": "apps.apple.com/app/id6793563591",
    },
    "es": {
        "fecha":    "12 DE AGOSTO DE 2026",
        "hook1":    ["80 SEGUNDOS"],
        "hook2":    ["DE OSCURIDAD", "TOTAL"],
        "problema": ["MIRA AL CIELO,"],
        "problema2": ["NO A LA PANTALLA."],
        "voz_tit":  "POR ESO LA APP TE HABLA",
        "cues": [
            (7.00, 8.69, "Un minuto para el primer contacto."),
            (9.40, 11.47, "Contacto, el eclipse ha comenzado."),
            (12.20, 13.86, "Totalidad. Quitar el filtro."),
            (14.90, 15.51, "Disparar."),
        ],
        "proof1":   ["TIEMPOS DE CONTACTO", "EXACTOS, SIN INTERNET."],
        "proof2":   ["CADA AVISO, HABLADO", "EN SU SEGUNDO."],
        "cta_tit":  "CONTROL TIEMPOS",
        "cta_sub":  "Gratis en la App Store",
        "cta_pie":  "Busca:  Control Tiempos Eclipse",
        "cta_link": "apps.apple.com/app/id6793563591",
    },
}

# Tiempos de cada escena. Las de "prueba" y el cierre necesitan aire: con menos
# de tres segundos no da tiempo a leer una tarjeta de contactos ni la llamada
# final, que es la que tiene que quedarse grabada.
T_HOOK, T_PROB, T_VOZ, T_PROOF, T_CTA, T_FIN = 0.0, 3.2, 6.2, 16.0, 23.2, 29.6


def frame(t, g):
    base = Image.new("RGBA", (W, H), (*FONDO, 255))
    d = ImageDraw.Draw(base)

    # ---------------- Escena 1: gancho ----------------
    if t < T_PROB + 0.4:
        a = 1.0 - rampa(t, T_PROB - 0.3, T_PROB + 0.4)
        crece = rampa(t, 0.0, 1.6)
        r = int(150 + 60 * crece)
        c = corona(r, r * 0.32)
        esc = 0.85 + 0.15 * crece
        c = c.resize((int(c.width * esc), int(c.height * esc)), Image.LANCZOS)
        _componer(base, c, W / 2 - c.width / 2, 560 - c.height / 2, a)
        # disco lunar
        rr = int(r * esc)
        d.ellipse([W / 2 - rr, 560 - rr, W / 2 + rr, 560 + rr], fill=(*FONDO, int(255 * a)))

        texto(d, (W / 2, 1010), g["fecha"], bold(46), ORO,
              tracking=14, alpha=int(255 * a * rampa(t, 0.3, 1.0)))
        multilinea(d, W / 2, 1250, g["hook1"], negra_ajustada(d, g["hook1"], 190), BLANCO,
                   alpha=int(255 * a * rampa(t, 0.7, 1.4)))
        multilinea(d, W / 2, 1500, g["hook2"], negra_ajustada(d, g["hook2"], 112), BLANCO,
                   alpha=int(255 * a * rampa(t, 1.0, 1.7)))

    # ---------------- Escena 2: problema ----------------
    if T_PROB - 0.2 < t < T_VOZ + 0.4:
        a1 = aparecer(t, T_PROB, 0.45, 1.7, 0.4)
        a2 = aparecer(t, T_PROB + 1.3, 0.45, 1.3, 0.4)
        multilinea(d, W / 2, 830, g["problema"], negra_ajustada(d, g["problema"], 104), BLANCO, alpha=int(255 * a1))
        multilinea(d, W / 2, 1120, g["problema2"], negra_ajustada(d, g["problema2"], 104), ORO, alpha=int(255 * a2))

    # ---------------- Escena 3: la voz ----------------
    if T_VOZ - 0.2 < t < T_PROOF + 0.3:
        a = rampa(t, T_VOZ - 0.2, T_VOZ + 0.3) * (1 - rampa(t, T_PROOF - 0.4, T_PROOF + 0.3))
        texto(d, (W / 2, 430), g["voz_tit"], bold(44), ORO, tracking=10, alpha=int(255 * a))

        # Onda de audio: se agita solo mientras suena una frase.
        hablando = any(ini - 0.15 < t < fin + 0.15 for ini, fin, _ in g["cues"])
        barras, ancho, hueco = 41, 9, 13
        total = barras * ancho + (barras - 1) * hueco
        x0 = W / 2 - total / 2
        for i in range(barras):
            centro = 1 - abs(i - barras // 2) / (barras / 2)
            if hablando:
                h = 18 + 150 * centro * (0.45 + 0.55 * abs(math.sin(t * 11 + i * 0.7)))
            else:
                h = 12 + 10 * centro * (0.5 + 0.5 * math.sin(t * 2.2 + i * 0.35))
            x = x0 + i * (ancho + hueco)
            d.rounded_rectangle([x, 700 - h / 2, x + ancho, 700 + h / 2],
                                radius=ancho / 2, fill=(*ORO, int(230 * a)))

        # Subtítulos sincronizados con la voz real.
        for ini, fin, frase in g["cues"]:
            av = aparecer(t, ini - 0.2, 0.25, (fin - ini) + 0.25, 0.45)
            if av > 0.01:
                lineas = _partir(d, frase, bold(66), W - 200)
                multilinea(d, W / 2, 1080, lineas, bold(66), BLANCO, alpha=int(255 * av))

    # ---------------- Escena 4: pruebas ----------------
    if T_PROOF - 0.3 < t < T_CTA + 0.3:
        a1 = aparecer(t, T_PROOF, 0.45, 2.75, 0.4)
        a2 = aparecer(t, T_PROOF + 3.6, 0.45, 2.75, 0.4)
        if a1 > 0.01:
            desliz = (1 - suave(min(1, (t - T_PROOF) / 0.8))) * 70
            tarjeta = recorte(f"s3_verification{SUFIJO}", (0.025, 0.578, 0.975, 0.873), 920)
            pegar_con_brillo(base, tarjeta, W / 2, 880 + desliz, a1)
            multilinea(d, W / 2, 1450, g["proof1"], negra_ajustada(d, g["proof1"], 62), BLANCO,
                       tracking=1, alpha=int(255 * a1))
        if a2 > 0.01:
            desliz = (1 - suave(min(1, (t - T_PROOF - 3.6) / 0.8))) * 70
            tarjeta = recorte(f"s5_execution{SUFIJO}", (0.025, 0.055, 0.975, 0.360), 920)
            pegar_con_brillo(base, tarjeta, W / 2, 880 + desliz, a2)
            multilinea(d, W / 2, 1450, g["proof2"], negra_ajustada(d, g["proof2"], 62), BLANCO,
                       tracking=1, alpha=int(255 * a2))

    # ---------------- Escena 5: cierre ----------------
    if t > T_CTA - 0.3:
        a = rampa(t, T_CTA - 0.3, T_CTA + 0.35)
        salida = 1 - rampa(t, T_FIN - 0.45, T_FIN)
        a *= salida

        ic = Image.open(AQUI / "icon.png").convert("RGB").resize((380, 380), Image.LANCZOS)
        m = Image.new("L", ic.size, 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, 379, 379], radius=88, fill=255)
        icono = Image.new("RGBA", ic.size)
        icono.paste(ic, (0, 0))
        icono.putalpha(m)

        glow = Image.new("RGBA", (520, 520), (0, 0, 0, 0))
        ImageDraw.Draw(glow).rounded_rectangle([70, 70, 450, 450], radius=88, fill=(*ORO, 90))
        _componer(base, glow.filter(ImageFilter.GaussianBlur(50)), W / 2 - 260, 640 - 260, a)
        _componer(base, icono, W / 2 - 190, 640 - 190, a)

        texto(d, (W / 2, 1000), g["cta_tit"], negra_ajustada(d, [g["cta_tit"]], 96), BLANCO, tracking=4, alpha=int(255 * a))
        texto(d, (W / 2, 1110), g["cta_sub"], regular(50), ORO, alpha=int(255 * a))
        texto(d, (W / 2, 1275), g["cta_pie"], regular(40), (155, 155, 160),
              alpha=int(255 * a * rampa(t, T_CTA + 0.6, T_CTA + 1.2)))

        # La URL no es pulsable en un Reel, pero se lee y se teclea. El enlace
        # de verdad va en la biografía del perfil.
        a_link = a * rampa(t, T_CTA + 1.4, T_CTA + 2.0)
        d.rounded_rectangle([W / 2 - 400, 1380, W / 2 + 400, 1478],
                            radius=49, outline=(*ORO, int(150 * a_link)), width=3)
        texto(d, (W / 2, 1429), g["cta_link"], regular(38), ORO, alpha=int(255 * a_link))

    return base.convert("RGB")


def _partir(d, frase, font, ancho_max):
    palabras, lineas, actual = frase.split(), [], ""
    for p in palabras:
        prueba = (actual + " " + p).strip()
        if d.textlength(prueba, font=font) <= ancho_max:
            actual = prueba
        else:
            lineas.append(actual)
            actual = p
    if actual:
        lineas.append(actual)
    return lineas


def main():
    global SUFIJO
    idioma = sys.argv[1] if len(sys.argv) > 1 else "en"
    SUFIJO = "_es" if idioma == "es" else ""
    g = GUION[idioma]
    salida = AQUI / f"frames_{idioma}"
    salida.mkdir(exist_ok=True)
    for f in salida.glob("*.png"):
        f.unlink()

    n = int(T_FIN * FPS)
    for i in range(n):
        frame(i / FPS, g).save(salida / f"f{i:05d}.png")
        if i % 60 == 0:
            print(f"  {i}/{n}", flush=True)
    print(f"{n} fotogramas en {salida}")


if __name__ == "__main__":
    main()
