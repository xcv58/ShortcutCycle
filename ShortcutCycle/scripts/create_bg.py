from PIL import Image, ImageDraw

def create_dmg_background(output_path):
    width = 650
    height = 400
    background_color = (255, 255, 255)  # White
    arrow_color = (200, 200, 200)       # Light gray

    image = Image.new("RGB", (width, height), background_color)
    draw = ImageDraw.Draw(image)

    # Coordinates
    app_icon_pos = (175, 120)
    app_folder_pos = (475, 120)
    
    # Arrow parameters
    head_size = 30
    arrow_width = 10
    
    arrow_start = (app_icon_pos[0] + 70, app_icon_pos[1])
    # Line stops at the base of the arrow head
    arrow_end_tip = (app_folder_pos[0] - 70, app_folder_pos[1])
    arrow_line_end = (arrow_end_tip[0] - head_size, arrow_end_tip[1])
    
    # Draw arrow line (stem)
    draw.line([arrow_start, arrow_line_end], fill=arrow_color, width=arrow_width)
    
    # Draw arrow head
    draw.polygon([
        (arrow_end_tip[0], arrow_end_tip[1]),
        (arrow_end_tip[0] - head_size, arrow_end_tip[1] - head_size // 2),
        (arrow_end_tip[0] - head_size, arrow_end_tip[1] + head_size // 2)
    ], fill=arrow_color)

    # Save
    image.save(output_path)
    print(f"Generated {output_path}")

if __name__ == "__main__":
    create_dmg_background("scripts/dmg_background.png")
