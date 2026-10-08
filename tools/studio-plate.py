# Plaque de studio fixe : la voiture est générée DEDANS par images/edits.
from PIL import Image, ImageFilter
import math, sys
N=1024
def mix(a,b,t):
    t=max(0,min(1,t)); return tuple(a[i]+(b[i]-a[i])*t for i in range(3))
top=(0x2a,0x2b,0x31); wall=(0x15,0x16,0x1a); horizon=(0x26,0x27,0x2d); floor_far=(0x1e,0x1f,0x24); front=(0x09,0x09,0x0b)
H=0.60  # ligne d'horizon mur/sol (doux, cyclorama)
img=Image.new("RGB",(N,N))
px=img.load()
for y in range(N):
    v=y/N
    if v<H-0.06: c=mix(top,wall,v/(H-0.06))
    elif v<H+0.02: c=mix(wall,horizon,(v-(H-0.06))/0.08)
    else: c=mix(horizon,front,((v-(H+0.02))/(1-(H+0.02)))**0.9)
    for x in range(N):
        u=x/N
        # projecteur au-dessus (halo froid)
        d=math.hypot((u-0.5)/0.75,(v+0.1)/0.95); light=max(0,1-d)*0.10
        # flaque de lumière au sol
        f=math.hypot((u-0.5)/0.55,(v-0.76)/0.12); pool=max(0,1-f)**1.5*0.13 if v>H-0.02 else 0
        # vignettage
        g=math.hypot((u-0.5)/0.8,(v-0.48)/0.85); vig=max(0,(g-0.6)/0.4)*0.45
        r=[c[i]+(228-c[i])*(light+pool) for i in range(3)]
        r=[r[i]*(1-min(vig,0.6)) for i in range(3)]
        px[x,y]=tuple(int(round(k)) for k in r)
img=img.filter(ImageFilter.GaussianBlur(1.2))
img.save(sys.argv[1],"PNG")
