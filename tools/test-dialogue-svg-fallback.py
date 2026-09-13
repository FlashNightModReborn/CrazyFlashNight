"""验证 SVG 后备栅格化的尺寸、透明剪裁与无效输入边界。"""
from pathlib import Path
import tempfile

from PIL import Image
from dialogue_svg_fallback import rasterize_svg


def main():
    with tempfile.TemporaryDirectory(prefix="cf7-dialogue-svg-") as directory:
        root = Path(directory)
        svg = root / "source.svg"
        svg.write_text('''<svg xmlns="http://www.w3.org/2000/svg" width="40px" height="30px">
          <defs><clipPath id="window"><rect x="10" y="5" width="20" height="20"/></clipPath></defs>
          <g clip-path="url(#window)"><path fill="#eebbaa" d="M0 0H40V30H0Z"/></g></svg>''', encoding="utf-8")
        png = root / "output.png"
        evidence = rasterize_svg(svg, png, 2)
        with Image.open(png) as image:
            rgba = image.convert("RGBA")
            assert image.size == (80, 60)
            assert rgba.getbbox() == (20, 10, 60, 50)
            assert rgba.getpixel((40, 30)) == (238, 187, 170, 255)
            assert rgba.getpixel((0, 0))[3] == 0
        assert evidence["renderer"] == "ffdec-svg-cairosvg"
        evidence = rasterize_svg(svg, png, 2, resolution_scale=4)
        with Image.open(png) as image:
            assert image.size == (320, 240)
            assert image.convert("RGBA").getchannel("A").getbbox() == (80, 40, 240, 200)
        assert evidence["resolutionScale"] == 4
        for scale in (0, 33, 1.5):
            try:
                rasterize_svg(svg, png, 2, resolution_scale=scale)
            except ValueError:
                pass
            else:
                raise AssertionError(f"accepted invalid resolution scale {scale}")
        for zoom in (0, 9, 1.5):
            try:
                rasterize_svg(svg, png, zoom)
            except ValueError:
                pass
            else:
                raise AssertionError(f"accepted invalid zoom {zoom}")
    print("dialogue SVG fallback: dimensions, transparency, clipping and bounds passed")


if __name__ == "__main__":
    main()
