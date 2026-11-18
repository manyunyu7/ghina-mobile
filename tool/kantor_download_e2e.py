"""Run only against the isolated Pixel emulator with the probe APK installed."""
import hashlib
import selectors
import subprocess
import time
import xml.etree.ElementTree as ET
import json
from pathlib import Path

ADB = str(Path.home() / 'Library/Android/sdk/platform-tools/adb')
DEVICE = 'emulator-5554'  # Never fall back to an owner's USB phone.
PACKAGE = 'com.henryaugusta.ravel'


def adb(*args, check=True):
    return subprocess.run([ADB, '-s', DEVICE, *args], check=check,
                          capture_output=True, text=True).stdout.strip()


assert adb('shell', 'getprop', 'ro.kernel.qemu') == '1', 'Emulator required'
stream = subprocess.Popen([ADB, '-s', DEVICE, 'logcat', '-T', '1', '-s', 'flutter'],
                          stdout=subprocess.PIPE, text=True)
sel = selectors.DefaultSelector()
sel.register(stream.stdout, selectors.EVENT_READ)
try:
    print(adb('shell', 'am', 'start', '-n', PACKAGE + '/com.henryaugusta.ghina.MainActivity'), flush=True)
    ready = False
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if not sel.select(1):
            continue
        line = stream.stdout.readline()
        if 'DOWNLOAD_PROBE' in line:
            print(line.strip(), flush=True)
        if 'DOWNLOAD_PROBE FAILED' in line:
            raise AssertionError('native probe failed')
        if 'DOWNLOAD_PROBE BACKGROUND_READY' in line:
            ready = True
            break
    assert ready, 'No active download reported by native probe'
finally:
    stream.terminate()
    stream.wait(timeout=5)
    sel.close()

pid = adb('shell', 'pidof', PACKAGE)
assert pid, 'probe process not found'
adb('shell', 'input', 'keyevent', '3')
adb('shell', 'run-as', PACKAGE, 'kill', '-9', *pid.split())
adb('shell', 'input', 'keyevent', '223')
assert not adb('shell', 'pidof', PACKAGE, check=False), 'App process must be dead'
print('APP_PROCESS_DEAD_SCREEN_OFF', flush=True)

xml = adb('shell', 'run-as', PACKAGE, 'cat', 'shared_prefs/kantor_downloads.xml')
records = [json.loads(e.text) for e in ET.fromstring(xml).findall('string')]
record = next(r for r in records if r['name'] == 'background-test-2.bin')
location = '/sdcard/' + record['location']
expected = hashlib.sha256(bytes(range(256)) * (8 * 1024 * 1024 // 256)).hexdigest()
deadline = time.monotonic() + 90
while time.monotonic() < deadline:
    output = adb('shell', 'sha256sum', location, check=False)
    if output.startswith(expected):
        break
    time.sleep(2)
else:
    raise AssertionError('Downloaded bytes did not match fixture')
assert not adb('shell', 'pidof', PACKAGE, check=False), 'App must stay dead until completion'
print('BACKGROUND_DOWNLOAD_SHA256_PASS', expected, flush=True)
adb('shell', 'input', 'keyevent', '224')
adb('shell', 'wm', 'dismiss-keyguard')
adb('shell', 'am', 'start', '-n', PACKAGE + '/com.henryaugusta.ghina.MainActivity')
print('APP_REOPENED_CHECK_RESTORED_STATUS', flush=True)
