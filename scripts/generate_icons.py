#!/usr/bin/env python3
"""Convert SVG to PNG at multiple resolutions for Flutter app icons."""
import os
import sys
from pathlib import Path

try:
    import cairosvg
except ImportError:
    print("Installing cairosvg...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "cairosvg", "pillow"])
    import cairosvg

from PIL import Image

SVG_PATH = "/root/hermes/deep_focus/assets/icon/app_icon.svg"
OUTPUT_DIR = "/root/hermes/deep_focus/assets/icon"

SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
    "ios_20": 20,
    "ios_29": 29,
    "ios_40": 40,
    "ios_57": 57,
    "ios_60": 60,
    "ios_76": 76,
    "ios_80": 80,
    "ios_87": 87,
    "ios_120": 120,
    "ios_152": 152,
    "ios_167": 167,
    "ios_180": 180,
    "ios_1024": 1024,
}

def convert_svg_to_png(svg_path, output_path, size):
    """Convert SVG to PNG at specified size."""
    try:
        cairosvg.svg2png(
            url=svg_path,
            write_to=output_path,
            output_width=size,
            output_height=size,
            background_color=None,  # Transparent background
        )
        print(f"  ✓ {output_path} ({size}x{size})")
        return True
    except Exception as e:
        print(f"  ✗ Failed {output_path}: {e}")
        return False

def create_rounded_png(input_path, output_path, size, corner_radius_ratio=0.28):
    """Add rounded corners to match Android adaptive icon style."""
    try:
        img = Image.open(input_path).convert("RGBA")
        img = img.resize((size, size), Image.Resampling.LANCZOS)
        
        # Create rounded corners mask
        mask = Image.new("L", (size, size), 0)
        from PIL import ImageDraw
        draw = ImageDraw.Draw(mask)
        radius = int(size * corner_radius_ratio)
        draw.rounded_rectangle([0, 0, size, size], radius=radius, fill=255)
        
        # Apply mask
        output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        output.paste(img, (0, 0), mask)
        output.save(output_path, "PNG")
        return True
    except Exception as e:
        print(f"  ✗ Rounded corners failed for {output_path}: {e}")
        return False

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    if not os.path.exists(SVG_PATH):
        print(f"SVG not found at {SVG_PATH}")
        sys.exit(1)
    
    print(f"Converting {SVG_PATH} to PNG at multiple sizes...")
    
    # First, create base PNGs
    success = 0
    for name, size in SIZES.items():
        output_path = os.path.join(OUTPUT_DIR, f"app_icon_{name}.png")
        if convert_svg_to_png(SVG_PATH, output_path, size):
            success += 1
    
    # Create mipmap directories and copy to Android res
    mipmap_dirs = {
        "mdpi": "mipmap-mdpi",
        "hdpi": "mipmap-hdpi", 
        "xhdpi": "mipmap-xhdpi",
        "xxhdpi": "mipmap-xxhdpi",
        "xxxhdpi": "mipmap-xxxhdpi",
    }
    
    for density, mipmap_dir in mipmap_dirs.items():
        src = os.path.join(OUTPUT_DIR, f"app_icon_{density}.png")
        dst_dir = f"/root/hermes/deep_focus/android/app/src/main/res/{mipmap_dir}"
        dst = os.path.join(dst_dir, "ic_launcher.png")
        os.makedirs(dst_dir, exist_ok=True)
        if os.path.exists(src):
            import shutil
            shutil.copy2(src, dst)
            print(f"  ✓ Copied to {dst}")
    
    # Create the main app icon for flutter_launcher_icons
    main_icon = os.path.join(OUTPUT_DIR, "app_icon.png")
    if os.path.exists(os.path.join(OUTPUT_DIR, "app_icon_xxxhdpi.png")):
        import shutil
        shutil.copy2(os.path.join(OUTPUT_DIR, "app_icon_xxxhdpi.png"), main_icon)
        print(f"  ✓ Created main icon at {main_icon} (192x192)")
    
    # Also create foreground icon for adaptive icon
    # For adaptive icon foreground, we need a version with transparent background
    # The foreground should have the icon centered with some padding
    # Let's just copy the main icon for now
    foreground_path = os.path.join(OUTPUT_DIR, "app_icon_foreground.png")
    if os.path.exists(main_icon):
        import shutil
        shutil.copy2(main_icon, foreground_path)
        print(f"  ✓ Created foreground icon at {foreground_path}")
    
    print(f"\nDone! {success}/{len(SIZES)} conversions successful.")

if __name__ == "__main__":
    main()