# Verify vector coordinates
import xml.etree.ElementTree as ET

# Logo bounds in docuray_logo.svg:
# Path 1 min/max X: 382 to 1501
# Path 1 min/max Y: 399 to 1440
# Path 2 min/max X: 497 to 1654
# Path 2 min/max Y: 685 to 1609
# Overall bounding box: X in [382, 1654] (width = 1272)
#                       Y in [399, 1609] (height = 1210)
# Center: cx = 1018, cy = 1004

print(f"Logo center: (1018, 1004), dimensions: 1272 x 1210")

# For light splash: viewport 1600x1600, logo centered at (800, 800)
# translateX = 800 - 1018 = -218
# translateY = 800 - 1004 = -204
# Logo size in viewport: 1272/1600 = ~80% of width.
# If we want a nice comfortable margin, e.g. logo width ~1000 in 1600 viewport:
# scale = 0.75, translateX = 800 - 1018*0.75 = 800 - 763.5 = +36.5
# translateY = 800 - 1004*0.75 = 800 - 753 = +47

# For dark splash: white tile around it:
# Viewport 2000x2000:
# Rounded rect tile: (250, 250) to (1750, 1750), width 1500, height 1500, rx=300
# Logo centered in tile at (1000, 1000):
# Logo size inside 1500 tile: ~1000px (scale = 0.8)
# scale = 0.8
# translateX = 1000 - 1018*0.8 = 1000 - 814.4 = 185.6
# translateY = 1000 - 1004*0.8 = 1000 - 803.2 = 196.8
