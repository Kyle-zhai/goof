"""Generates the Goof icon artwork as SVG.

    python3 design/icon.py design/AppIcon.svg
    python3 design/icon.py design/AppIcon-small.svg --small   # simpler art for 16 and 32 px
    python3 design/icon.py design/Logo.svg --logo             # just the squircle: no margin, no shadow

AppIcon.appiconset and Logo.imageset in App/Goof/Resources/Assets.xcassets are
renders of these files (any SVG renderer that supports filters, such as a browser).
"""
import math
import sys


def squircle(cx, cy, size, n=5.0, steps=720):
    """Apple-like continuous-corner square as a superellipse path."""
    a = size / 2
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = cx + a * math.copysign(abs(c) ** (2 / n), c)
        y = cy + a * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{x:.2f},{y:.2f}")
    return "M" + " L".join(pts) + " Z"


def bubble_path(cx, cy, w, h, r):
    """A rounded speech bubble body with a tail at the bottom left."""
    x0, y0, x1, y1 = cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
    # Tail: a short, rounded wedge under the left side, pointing down-left.
    tx0 = x0 + w * 0.16
    tx1 = x0 + w * 0.38
    tip = (x0 + w * 0.07, y1 + h * 0.19)
    return (
        f"M{x0 + r},{y0} "
        f"H{x1 - r} A{r},{r} 0 0 1 {x1},{y0 + r} "
        f"V{y1 - r} A{r},{r} 0 0 1 {x1 - r},{y1} "
        f"H{tx1} "
        f"C{tx1 - w * 0.03},{y1 + h * 0.09} {tip[0] + w * 0.09},{tip[1] + h * 0.005} {tip[0]},{tip[1]} "
        f"Q{tip[0] - w * 0.022},{tip[1] - h * 0.01} {tip[0] + w * 0.006},{tip[1] - h * 0.04} "
        f"C{tx0 + w * 0.01},{y1 + h * 0.08} {tx0 + w * 0.01},{y1 + h * 0.03} {tx0},{y1} "
        f"H{x0 + r} A{r},{r} 0 0 1 {x0},{y1 - r} "
        f"V{y0 + r} A{r},{r} 0 0 1 {x0 + r},{y0} Z"
    )


def icon_svg(small=False, logo=False):
    W = 1024
    view = "100 100 824 824" if logo else f"0 0 {W} {W}"
    body_filter = "" if logo else ' filter="url(#iconShadow)"'
    body = squircle(512, 512, 824)
    bx, by, bw, bh = 468, 482, 552, 440
    streaks = "" if small else f"""
    <g fill="url(#trail)">
      <rect x="700" y="384" width="200" height="34" rx="17"/>
      <rect x="724" y="472" width="170" height="34" rx="17" opacity="0.8"/>
      <rect x="704" y="560" width="186" height="34" rx="17" opacity="0.62"/>
    </g>"""
    blush = "" if small else """
      <ellipse cx="368" cy="548" rx="36" ry="20" fill="#FF7E95" opacity="0.38"/>
      <ellipse cx="596" cy="540" rx="36" ry="20" fill="#FF7E95" opacity="0.38"/>"""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}">
  <defs>
    <linearGradient id="bg" x1="0.1" y1="0.05" x2="0.9" y2="0.95">
      <stop offset="0" stop-color="#FF9A62"/>
      <stop offset="0.48" stop-color="#FF5A5F"/>
      <stop offset="1" stop-color="#E2335E"/>
    </linearGradient>
    <radialGradient id="shine" cx="0.25" cy="0.12" r="0.75">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.32"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="bubbleFill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#FFEDEF"/>
    </linearGradient>
    <linearGradient id="trail" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0.25" stop-color="#FFFFFF" stop-opacity="0.95"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.2"/>
    </linearGradient>
    <filter id="iconShadow" x="-10%" y="-10%" width="120%" height="125%">
      <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000000" flood-opacity="0.28"/>
    </filter>
    <filter id="bubbleShadow" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="22" stdDeviation="22" flood-color="#8E1236" flood-opacity="0.38"/>
    </filter>
    <clipPath id="bodyClip"><path d="{body}"/></clipPath>
  </defs>
  <path d="{body}" fill="url(#bg)"{body_filter}/>
  <g clip-path="url(#bodyClip)">
    <path d="{body}" fill="url(#shine)"/>
    {streaks}
    <g transform="rotate(-7 {bx} {by})">
      <path d="{bubble_path(bx, by, bw, bh, 200)}" fill="url(#bubbleFill)" filter="url(#bubbleShadow)"/>
      <!-- eyes -->
      <ellipse cx="398" cy="452" rx="{46 if small else 40}" ry="{58 if small else 52}" fill="#2B1631"/>
      <ellipse cx="560" cy="446" rx="{54 if small else 48}" ry="{66 if small else 60}" fill="#2B1631"/>
      <circle cx="{412 if small else 411}" cy="{432 if small else 434}" r="{0 if small else 13}" fill="#FFFFFF"/>
      <circle cx="{577 if small else 576}" cy="{423 if small else 424}" r="{0 if small else 15}" fill="#FFFFFF"/>
      {blush}
      <!-- grin -->
      <path d="M404 552 Q474 628 562 546" fill="none" stroke="#2B1631" stroke-width="{30 if small else 24}" stroke-linecap="round"/>
      <!-- tongue -->
      <g transform="rotate(16 528 586)">
        <path d="M490 574 C488 616 500 652 532 654 C566 656 574 616 570 572 Z" fill="#FF6F8E"/>
        <path d="M531 586 L531 628" stroke="#E04A6C" stroke-width="8" stroke-linecap="round" opacity="{0 if small else 1}"/>
      </g>
    </g>
  </g>
</svg>
"""


if __name__ == "__main__":
    out = sys.argv[1]
    small = "--small" in sys.argv
    logo = "--logo" in sys.argv
    with open(out, "w") as f:
        f.write(icon_svg(small, logo))
