"""Extracts data/island_map.png (R=height, G=biome class, B=tree density) from the reference island image."""
from PIL import Image, ImageDraw
import numpy as np, json, sys
from scipy import ndimage
SRC = sys.argv[1] if len(sys.argv) > 1 else "/root/.claude/uploads/40b6c791-704e-5707-93d1-fb95a07f32bb/3820f70b-image.png"
src = Image.open(SRC).convert("RGB"); W,H = src.size
SIZE=720.0; N=241; px_per_m = W/SIZE
img = np.asarray(src).astype(np.float32)/255.0
r,g,b = img[...,0],img[...,1],img[...,2]
mx = img.max(-1); mn = img.min(-1); d = mx-mn+1e-6
v = mx; s = d/(mx+1e-6)
h = np.zeros_like(mx)
m = (mx==r); h[m] = ((g-b)/d)[m] % 6
m = (mx==g); h[m] = ((b-r)/d+2)[m]
m = (mx==b); h[m] = ((r-g)/d+4)[m]
h = h*60
lum = 0.3*r+0.59*g+0.11*b
def poly_mask(poly):
    mk = Image.new("L",(W,H),0); ImageDraw.Draw(mk).polygon(poly, fill=255); return np.asarray(mk)>0
sea = (h>190)&(h<250)&(s>0.45)&(v>0.15)
land = ~sea
land = ndimage.binary_opening(land, iterations=2); land = ndimage.binary_closing(land, iterations=3)
lab, n = ndimage.label(land); sizes = ndimage.sum(land, lab, range(1,n+1))
islets=[]
for i,sz in enumerate(sizes, start=1):
    if sz < 1200:
        ys,xs = np.where(lab==i); islets.append((float(xs.mean()), float(ys.mean()), float(np.sqrt(sz)*0.6)))
        land[lab==i]=False
# the harbour town is its own island: the strait under the aqueduct runs on south into the bay
CHANNEL = poly_mask([(845,185),(958,185),(962,205),(985,268),(1005,330),(1040,420),(985,430),(950,330),(922,270),(905,235),(845,238)])
land[CHANNEL] = False
sea = ~land
# region priors (image px)
MOUNT = poly_mask([(60,120),(300,20),(720,30),(900,120),(880,260),(760,300),(560,290),(400,330),(150,330),(40,240)])
FARM  = poly_mask([(200,420),(560,380),(640,420),(660,520),(560,640),(420,700),(250,660),(180,540)])
TOWN  = poly_mask([(960,60),(1300,40),(1480,90),(1560,200),(1500,330),(1400,360),(1230,400),(1080,360),(960,290),(930,190)])
BAD   = poly_mask([(760,560),(900,470),(1060,440),(1240,470),(1400,560),(1440,700),(1340,800),(1130,850),(880,840),(740,760),(700,640)])
LAKE  = poly_mask([(980,700),(1040,690),(1120,700),(1170,740),(1150,790),(1080,800),(1000,780),(960,740)])
cls = np.full((H,W), 2, np.uint8)          # default land: forest/scrub
pale = (s<0.30)&(v>0.55)
orange = (h>=8)&(h<=38)&(s>0.38)&(v>0.35)
yellowgreen = (h>38)&(h<75)&(v>0.45)
# local fractions of each colour cue (the map is a mix of rock faces and tree canopies)
pale_f = ndimage.uniform_filter(pale.astype(np.float32), 25)
yg_f = ndimage.uniform_filter(yellowgreen.astype(np.float32), 25)
or_f = ndimage.uniform_filter(orange.astype(np.float32), 25)
cls[MOUNT] = 1
cls[FARM] = 3
cls[BAD & ((or_f > 0.15) | (pale_f > 0.2))] = 4
cls[TOWN] = 5
def majority(c, k):
    votes = np.stack([ndimage.uniform_filter((c==i).astype(np.float32), k) for i in range(8)], -1)
    return votes.argmax(-1).astype(np.uint8)
cls = majority(cls, 9)
cls[~land] = 0
dist_sea = ndimage.distance_transform_edt(land)
beach = land & (dist_sea<8) & (cls!=1) & (cls!=5) & (cls!=4)
cls[beach]=6
lake = LAKE & (b > r + 0.08) & (b > g)
cls[lake] = 7
hgt = np.zeros((H,W), np.float32)
hgt[cls==6] = 1.8; hgt[cls==3] = 5.0; hgt[cls==2] = 7.0; hgt[cls==5] = 8.0; hgt[cls==4] = 12.0
mt = cls==1
hgt[mt] = 20.0 + 30.0*np.clip((lum[mt]-0.45)/0.35,0,1) + np.clip(dist_sea[mt]/40.0,0,1)*12
hgt[cls==4] += np.clip(dist_sea[cls==4]/30.0,0,1)*10
hgt[cls==2] += np.clip(dist_sea[cls==2]/60.0,0,1)*7
dist_land = ndimage.distance_transform_edt(~land)
hgt[cls==0] = -1.2 - np.clip(dist_land[cls==0]/200.0,0,1)*9.0   # a wide shallow shelf, then the deep
hgt[cls==7] = -3.0
# the lake sits in a basin: the badlands drop to a gentle shore within ~30 m of the water
dist_lake = ndimage.distance_transform_edt(cls!=7)
basin = np.clip((dist_lake-18)/110.0, 0, 1)
bad = cls==4
hgt[bad] = 0.8 + (hgt[bad]-0.8)*basin[bad]
hgt = ndimage.gaussian_filter(hgt, 5)
dens = np.zeros((H,W), np.float32)
dens[cls==2] = np.clip((0.62-v[cls==2])/0.35,0,1)
dens[cls==1] = np.clip((0.55-v[cls==1])/0.3,0,1)*0.6
dens[cls==5] = np.clip((0.5-v[cls==5])/0.3,0,1)*0.5
dens = ndimage.gaussian_filter(dens, 3)
out = np.zeros((N,N,3), np.uint8)
for j in range(N):
    for i in range(N):
        wx = i/(N-1)*SIZE - SIZE/2; wz = j/(N-1)*SIZE - SIZE/2
        px = (wx + SIZE/2)*px_per_m; py = wz*px_per_m + H/2
        # the painting is 720 x 405 m: rows beyond its top/bottom edge carry on from the nearest edge pixel
        x=int(min(max(px,0),W-1)); y=int(min(max(py,0),H-1))
        beyond = (abs(py - y)) / px_per_m   # metres past the painting's edge: keep deepening the sea
        h = hgt[y,x] - beyond * 0.12 if cls[y,x] == 0 else hgt[y,x]
        if True:
            out[j,i,0] = int(np.clip((h+10)/90*255,0,255)); out[j,i,1] = cls[y,x]; out[j,i,2] = int(dens[y,x]*255)
        else:
            out[j,i,0] = int((-10+10)/90*255); out[j,i,1]=0; out[j,i,2]=0
# sea depth is recomputed on the world grid itself (true distance to land, in metres), so the shelf
# is the same width all round the island and beyond the painting's edge
land_grid = (out[...,1] != 0) & (out[...,1] != 7)
dist_m = ndimage.distance_transform_edt(~land_grid) * (SIZE/(N-1))
sea_h = -1.2 - np.clip(dist_m/86.0, 0, 1)*9.0
sea_cells = out[...,1] == 0
out[sea_cells, 0] = np.clip((sea_h[sea_cells]+10)/90*255, 0, 255).astype(np.uint8)
Image.fromarray(out).save("data/island_map.png")
# a wider depth map for the sea shader (1000 m square): the shelf keeps its true width past the world's edge
SEA_SIZE = 1000.0; SN = 334
sea_map = np.zeros((SN, SN), np.uint8)
land_big = np.zeros((SN, SN), bool)
off = int(round((SEA_SIZE - SIZE) / 2 / (SEA_SIZE / (SN - 1))))
scale = (SEA_SIZE / (SN - 1)) / (SIZE / (N - 1))
for j in range(SN):
    for i in range(SN):
        gi = (i - off) * scale; gj = (j - off) * scale
        if 0 <= gi < N - 1 and 0 <= gj < N - 1:
            land_big[j, i] = land_grid[int(round(gj)), int(round(gi))]
dist_big = ndimage.distance_transform_edt(~land_big) * (SEA_SIZE / (SN - 1))
h_big = -1.2 - np.clip(dist_big / 86.0, 0, 1) * 9.0
sea_map[:] = np.clip((h_big + 10) / 90 * 255, 0, 255).astype(np.uint8)
sea_map[land_big] = 255
Image.fromarray(np.stack([sea_map] * 3, -1)).save("data/sea_depth.png")
pal = {0:(20,60,140),1:(230,225,210),2:(40,90,40),3:(170,170,60),4:(200,110,60),5:(190,80,60),6:(240,220,170),7:(60,130,190)}
prev = np.zeros((H,W,3),np.uint8)
for k,c in pal.items(): prev[cls==k]=c
Image.fromarray(prev).resize((W//2,H//2)).save("/tmp/biome_preview.png")
json.dump({"islets":islets, "px_per_m":px_per_m, "size":SIZE, "img_w":W, "img_h":H}, open("data/island_meta.json","w"))
print("islets:", len(islets)); print("class counts:", {k:int((cls==k).sum()) for k in range(8)})
