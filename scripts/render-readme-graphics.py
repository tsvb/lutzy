#!/usr/bin/env python3
# Draws docs/images/lut-cube.svg and docs/images/derive.svg for the README. Run from the package
# root; standard library only. Regenerate rather than hand-editing the SVGs.
import math, colorsys
INK="#8E8E93"; INK2="#6E6E73"
SANS="-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif"
MONO="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"

AZ,EL=math.radians(38),math.radians(24)
def proj3(x,y,z,cx,cy,e):
    x,y,z=x-.5,y-.5,z-.5
    ca,sa=math.cos(AZ),math.sin(AZ); x,z = x*ca+z*sa, -x*sa+z*ca
    ce,se=math.cos(EL),math.sin(EL); y,z = y*ce-z*se, y*se+z*ce
    return cx+x*e, cy-y*e, z
def proj(x,y,z,cx,cy,e):
    px,py,_=proj3(x,y,z,cx,cy,e); return px,py

def look(r,g,b):
    # a film-ish look: S-curve, teal shadows, warm highlights, slight desat
    def s(v): return v*v*(3-2*v)
    r,g,b = s(r),s(g),s(b)
    lum = 0.2126*r+0.7152*g+0.0722*b
    shadow = (1-lum)**2; hi = lum**2
    r += 0.18*hi - 0.12*shadow; g += 0.06*hi + 0.02*shadow; b += -0.10*hi + 0.22*shadow
    h,l,sat = colorsys.rgb_to_hls(*[min(1,max(0,v)) for v in (r,g,b)])
    r,g,b = colorsys.hls_to_rgb(h,l,sat*0.85)
    return tuple(min(1,max(0,v)) for v in (r,g,b))

def cube(cx,cy,e,n,f,out):
    V={'000':(0,0,0),'100':(1,0,0),'001':(0,0,1),'101':(1,0,1),'010':(0,1,0),'110':(1,1,0),'011':(0,1,1),'111':(1,1,1)}
    C={k:proj3(*v,cx,cy,e) for k,v in V.items()}
    far=min(C,key=lambda k:C[k][2])
    edges=[(a,b) for a in V for b in V if a<b and sum(c1!=c2 for c1,c2 in zip(a,b))==1]
    def line(a,b,dash):
        (x1,y1,_),(x2,y2,_)=C[a],C[b]
        d=' stroke-dasharray="3 4"' if dash else ''
        out.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{INK}" stroke-width="1"{d} stroke-linecap="round"/>')
    for a,b in edges:
        if far in (a,b): line(a,b,True)
    dots=[]
    for i in range(n):
        for j in range(n):
            for k in range(n):
                r,g,b=f(i/(n-1),j/(n-1),k/(n-1))
                px,py,depth=proj3(r,g,b,cx,cy,e)
                dots.append((depth,px,py,r,g,b))
    dots.sort()
    for depth,px,py,r,g,b in dots:
        col='#%02x%02x%02x'%tuple(int(round(v*255)) for v in (r,g,b))
        rad=4.6+1.6*(depth+0.87)/1.74
        out.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{rad:.1f}" fill="{col}" stroke="rgba(0,0,0,0.25)" stroke-width="0.6"/>')
    for a,b in edges:
        if far not in (a,b): line(a,b,False)

def lut_cube_svg():
    W,H=720,318; out=[]
    out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{SANS}" font-size="13">')
    e=150
    cube(190,150,e,4,lambda x,y,z:(x,y,z),out)
    cube(530,150,e,4,look,out)
    # arrow
    out.append(f'<path d="M318 152 H398" stroke="{INK}" stroke-width="1.2" fill="none" stroke-linecap="round"/>')
    out.append(f'<path d="M392 146 L399 152 L392 158" stroke="{INK}" stroke-width="1.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
    out.append(f'<text x="358" y="140" text-anchor="middle" fill="{INK2}" font-family="{MONO}" font-size="12">.cube</text>')
    out.append(f'<text x="190" y="304" text-anchor="middle" fill="{INK2}">every color a photo can hold</text>')
    out.append(f'<text x="530" y="304" text-anchor="middle" fill="{INK2}">where the LUT sends each one</text>')
    out.append('</svg>')
    return '\n'.join(out)

def derive_svg():
    W,H=720,150; out=[]
    out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{SANS}" font-size="13">')
    def t(x,y,s,mono=False,anchor='start',fill=INK2):
        ff=f' font-family="{MONO}" font-size="12"' if mono else ''
        out.append(f'<text x="{x}" y="{y}" text-anchor="{anchor}" fill="{fill}"{ff}>{s}</text>')
    def p(d):
        out.append(f'<path d="{d}" stroke="{INK}" stroke-width="1.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
    def arrow(x,y):  # pointing right, tip at x
        p(f'M{x-7} {y-5} L{x} {y} L{x-7} {y+5}')
    # inputs
    t(0,44,'RAW',True); t(0,116,'JPEG',True)
    p('M44 40 H72'); arrow(72,40); t(80,44,'develop, neutral')
    p('M44 112 H72'); arrow(72,112); t(80,116,'decode')
    # merge
    p('M192 40 H228 V76 H244'); p('M128 112 H228 V76'); arrow(244,76)
    t(252,80,'align'); p('M292 76 H316'); arrow(316,76)
    t(324,80,'mask edges'); p('M404 76 H428'); arrow(428,76)
    t(436,80,'sample'); p('M490 76 H514'); arrow(514,76)
    t(522,80,'33³ cube')
    # outputs
    p('M590 76 H616 V40 H640'); arrow(640,40); t(648,44,'.cube',True)
    p('M616 76 V112 H640'); arrow(640,112); t(648,116,'report')
    out.append('</svg>')
    return '\n'.join(out)

open('docs/images/lut-cube.svg','w').write(lut_cube_svg())
open('docs/images/derive.svg','w').write(derive_svg())
print("written")
