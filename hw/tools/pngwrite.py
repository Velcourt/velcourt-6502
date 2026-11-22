# pngwrite.py - write an RGB image as PNG with only the standard library.
import zlib, struct
def write_png(path, width, height, rgb_rows):
    """rgb_rows: list of rows, each a bytes/bytearray of width*3 bytes."""
    raw = b"".join(b"\x00" + bytes(r) for r in rgb_rows)
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)
