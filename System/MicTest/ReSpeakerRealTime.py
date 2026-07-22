import usb.core
from tuning import Tuning
import time

dev = usb.core.find(idVendor=0x2886, idProduct=0x0018)

if dev is None:
    print("Not Found")
    exit()

mic = Tuning(dev)

print("Version:", mic.version)

while True:
    print(f"Direction: {mic.direction:3d}°")
    time.sleep(0.2)