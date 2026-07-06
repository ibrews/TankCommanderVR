"""Simulate standard GL cubemap sampling over an assembled 6x1 cubestrip and
reconstruct an equirectangular panorama from it, so seams can be checked
visually BEFORE uploading -- avoids another round of guess-a-slot-order,
upload, "still wrong". See intelligence/runbooks/meta-quest-app-lab-store-
assets.md "Face orientation convention" section for the ground truth this
implements (Meta's own OVRCubemapCapture.cs slot order: PX NX PY NY PZ NZ).

Usage:
  python tools/viewer_sim.py path/to/strip.png [out_equirect.png]

The strip is assumed to be 6 square faces side by side, slot order
PX, NX, PY, NY, PZ, NZ (standard OpenGL cubemap face order) -- NOT
"literal" left/right/up/down/front/back in the sense of which way a game
camera pointed; that mapping is exactly what the runbook's fix resolved.
"""
import sys
import numpy as np
from PIL import Image

def load_faces(strip_path):
    img = Image.open(strip_path).convert("RGB")
    w, h = img.size
    face_size = w // 6
    assert face_size == h, f"expected square faces, got {face_size}x{h}"
    arr = np.asarray(img)
    faces = [arr[:, i * face_size:(i + 1) * face_size, :] for i in range(6)]
    # GL order: PX, NX, PY, NY, PZ, NZ
    return dict(zip(["PX", "NX", "PY", "NY", "PZ", "NZ"], faces)), face_size

def sample_cubemap(faces, face_size, dirs):
    rx, ry, rz = dirs[..., 0], dirs[..., 1], dirs[..., 2]
    ax, ay, az = np.abs(rx), np.abs(ry), np.abs(rz)

    face_name = np.empty(rx.shape, dtype=object)
    sc = np.zeros_like(rx)
    tc = np.zeros_like(rx)
    ma = np.ones_like(rx)

    m_x = (ax >= ay) & (ax >= az)
    m_y = (~m_x) & (ay >= az)
    m_z = (~m_x) & (~m_y)

    px = m_x & (rx > 0)
    nx = m_x & ~(rx > 0)
    py = m_y & (ry > 0)
    ny = m_y & ~(ry > 0)
    pz = m_z & (rz > 0)
    nz = m_z & ~(rz > 0)

    face_name[px] = "PX"; sc[px] = -rz[px]; tc[px] = -ry[px]; ma[px] = rx[px]
    face_name[nx] = "NX"; sc[nx] = rz[nx];  tc[nx] = -ry[nx]; ma[nx] = -rx[nx]
    face_name[py] = "PY"; sc[py] = rx[py];  tc[py] = rz[py];  ma[py] = ry[py]
    face_name[ny] = "NY"; sc[ny] = rx[ny];  tc[ny] = -rz[ny]; ma[ny] = -ry[ny]
    face_name[pz] = "PZ"; sc[pz] = rx[pz];  tc[pz] = -ry[pz]; ma[pz] = rz[pz]
    face_name[nz] = "NZ"; sc[nz] = -rx[nz]; tc[nz] = -ry[nz]; ma[nz] = -rz[nz]

    s = (sc / ma + 1.0) / 2.0
    t = (tc / ma + 1.0) / 2.0  # t=0 at top row per GL convention

    out = np.zeros(dirs.shape[:-1] + (3,), dtype=np.uint8)
    for name, face_img in faces.items():
        mask = face_name == name
        if not np.any(mask):
            continue
        col = np.clip((s[mask] * (face_size - 1)).astype(np.int64), 0, face_size - 1)
        row = np.clip((t[mask] * (face_size - 1)).astype(np.int64), 0, face_size - 1)
        out[mask] = face_img[row, col]
    return out

def equirect_dirs(out_w, out_h):
    lon = (np.arange(out_w) + 0.5) / out_w * 2 * np.pi - np.pi           # -pi..pi
    lat = np.pi / 2 - (np.arange(out_h) + 0.5) / out_h * np.pi            # +pi/2..-pi/2
    lon, lat = np.meshgrid(lon, lat)
    x = np.cos(lat) * np.sin(lon)
    y = np.sin(lat)
    z = -np.cos(lat) * np.cos(lon)   # lon=0 -> -Z ("front" of this project)
    return np.stack([x, y, z], axis=-1)

def main():
    strip_path = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else "viewer_sim_equirect.png"
    faces, face_size = load_faces(strip_path)
    out_w, out_h = 2048, 1024
    dirs = equirect_dirs(out_w, out_h)
    equirect = sample_cubemap(faces, face_size, dirs)
    Image.fromarray(equirect).save(out_path)
    print(f"wrote {out_path} ({out_w}x{out_h}) from {strip_path}")

if __name__ == "__main__":
    main()
