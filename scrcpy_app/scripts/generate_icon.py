from PIL import Image, ImageDraw

def create_app_icon():
    size = 1024
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 1. Background Gradient (Indigo)
    # Using a solid deep indigo for the base as per plan
    draw.rounded_rectangle([0, 0, size, size], radius=size*0.2, fill=(26, 35, 126, 255))
    
    # 2. Device Frame (Rounded Rect)
    frame_padding = size * 0.15
    draw.rounded_rectangle(
        [frame_padding, frame_padding, size - frame_padding, size - frame_padding],
        radius=size*0.05,
        outline=(255, 255, 255, 80),
        width=int(size * 0.02)
    )

    # 3. Scanning Line (Cyan)
    line_y = size // 2
    draw.line([0, line_y, size, line_y], fill=(0, 188, 212, 255), width=int(size * 0.01))

    # 4. The Lens (White Dot)
    dot_radius = size * 0.03
    draw.ellipse(
        [size//2 - dot_radius, size//2 - dot_radius, size//2 + dot_radius, size//2 + dot_radius],
        fill=(255, 255, 255, 255)
    )

    img.save('assets/app_icon_source.png')
    print("App icon source generated.")

def create_tray_icon():
    size = 64
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Simplified monochrome version
    draw.rounded_rectangle([4, 4, size-4, size-4], radius=8, outline=(255, 255, 255, 255), width=4)
    draw.line([0, size//2, size, size//2], fill=(255, 255, 255, 255), width=2)
    draw.ellipse([size//2-3, size//2-3, size//2+3, size//2+3], fill=(255, 255, 255, 255))
    
    img.save('assets/tray_icon.png')
    print("Tray icon generated.")

if __name__ == "__main__":
    create_app_icon()
    create_tray_icon()
