"""Local emulator only: authenticated download, process death, encrypted retry."""
import hashlib
import json
from pathlib import Path
import selectors
import subprocess
import time
import xml.etree.ElementTree as ET

ADB = str(Path.home() / 'Library/Android/sdk/platform-tools/adb')
DEVICE = 'emulator-5554'
PACKAGE = 'com.henryaugusta.ravel'


def adb(*args, check=True):
    return subprocess.run([ADB, '-s', DEVICE, *args], check=check,
                          capture_output=True, text=True).stdout.strip()


def watch(marker):
    stream = subprocess.Popen([ADB, '-s', DEVICE, 'logcat', '-T', '1', '-s', 'flutter'],
                              stdout=subprocess.PIPE, text=True)
    sel = selectors.DefaultSelector()
    sel.register(stream.stdout, selectors.EVENT_READ)
    try:
        adb('shell', 'am', 'start', '-n', PACKAGE + '/com.henryaugusta.ghina.MainActivity')
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if not sel.select(1):
                continue
            line = stream.stdout.readline()
            if 'CHAT_PROBE' in line:
                print(line.strip(), flush=True)
            assert 'CHAT_PROBE FAILED' not in line, 'native probe failed'
            if marker in line:
                return
        raise AssertionError('probe timed out')
    finally:
        stream.terminate()
        stream.wait(timeout=5)
        sel.close()


assert adb('shell', 'getprop', 'ro.kernel.qemu') == '1', 'Emulator required'
watch('CHAT_PROBE BACKGROUND_READY')
pid = adb('shell', 'pidof', PACKAGE)
assert pid
adb('shell', 'input', 'keyevent', '3')
adb('shell', 'run-as', PACKAGE, 'kill', '-9', *pid.split())
adb('shell', 'input', 'keyevent', '223')
assert not adb('shell', 'pidof', PACKAGE, check=False)
print('CHAT_APP_DEAD_SCREEN_OFF', flush=True)
xml = adb('shell', 'run-as', PACKAGE, 'cat', 'shared_prefs/kantor_downloads.xml')
assert 'fixture-only' not in xml, 'credential must not be plaintext in app preferences'
records = [json.loads(e.text) for e in ET.fromstring(xml).findall('string')]
chat = [r for r in records if r.get('name', '').startswith('Chat-')]
assert len(chat) >= 2 and all(r.get('access') for r in chat)
print('CHAT_CREDENTIALS_ENCRYPTED_PASS', flush=True)
meta = next(r for r in records if r['name'] == 'Chat-background-49.bin')
expected = hashlib.sha256(bytes(range(256)) * (8 * 1024 * 1024 // 256)).hexdigest()
deadline = time.monotonic() + 90
while time.monotonic() < deadline:
    if adb('shell', 'sha256sum', '/sdcard/' + meta['location'], check=False).startswith(expected):
        break
    time.sleep(2)
else:
    raise AssertionError('background attachment hash mismatch')
assert not adb('shell', 'pidof', PACKAGE, check=False)
print('CHAT_BACKGROUND_SHA256_PASS', expected, flush=True)
adb('shell', 'input', 'keyevent', '224')
adb('shell', 'wm', 'dismiss-keyguard')
watch('CHAT_PROBE PERSISTED_AUTH_RETRY_PASS')
