import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('installer', ROOT/'linux/wow_ita_linux.py')
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


def digest(data):
    return hashlib.sha256(data).hexdigest()


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.root, self.game = base/'package', base/'game with spaces'
        self.game.mkdir()
        self.root.mkdir()
        (self.root/'metadata').mkdir()
        image = bytearray(1024)
        image[:2] = b'MZ'
        struct.pack_into('<I', image, 60, 128)
        image[128:132] = b'PE\0\0'
        struct.pack_into('<HH', image, 132, 0x14c, 2)
        struct.pack_into('<H', image, 148, 224)
        struct.pack_into('<H', image, 152, 0x10b)
        for header, name, size, start, flags in [(376,b'.text',128,512,0x60000020),
                                                 (416,b'.rsrc',128,640,0x40000040)]:
            image[header:header+len(name)] = name
            struct.pack_into('<II',image,header+16,size,start)
            struct.pack_into('<I',image,header+36,flags)
        struct.pack_into('<4I',image,640,0xfeef04bd,0x10000,0x30003,0x50000+12340)
        image[520:526] = b'ABCDEF'
        self.original = bytes(image)
        image[522] = ord('X')
        self.patched = bytes(image)
        (self.game/'Wow.exe').write_bytes(self.original)
        for relative in ['Data/a.txt', 'Data/b.txt']:
            p = self.root/'payload'/relative
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('new '+relative)
        (self.game/'Data').mkdir()
        (self.game/'Data/a.txt').write_text('original a')
        manifest = {'format': 1, 'package_version': '1.0.0',
                    'wow_exe': {'original_sha256': digest(self.original), 'patched_sha256': digest(self.patched)},
                    'required_files': ['Data/enUS/locale-enUS.MPQ'],
                    'patches': [{'offset': 522, 'old_hex': '43', 'new_hex': '58',
                                 'context_before_hex': '4142', 'context_after_hex': '444546'}]}
        (self.game/'Data/enUS').mkdir()
        (self.game/'Data/enUS/locale-enUS.MPQ').write_bytes(b'fixture')
        (self.root/'metadata/patch_manifest.json').write_text(json.dumps(manifest))
        (self.root/'metadata/SHA256SUMS').write_text(''.join(
            f'{app.sha256(p)}  {p.relative_to(self.root).as_posix()}\n' for p in app.payload_files(self.root)))
        self.baseline = self.game/'WoW-ITA-Backup/v1.0.0-baseline'

    def install(self):
        with contextlib.redirect_stdout(io.StringIO()):
            app.install(self.root, self.game)

    def uninstall(self):
        with contextlib.redirect_stdout(io.StringIO()):
            app.uninstall(self.root, self.game)

    def test_install_refresh_uninstall(self):
        self.install()
        initial = (self.baseline/'baseline.json').read_bytes()
        self.install()
        self.assertEqual(initial, (self.baseline/'baseline.json').read_bytes())
        self.assertEqual((self.game/'Wow.exe').read_bytes(), self.patched)
        self.uninstall()
        self.assertEqual((self.game/'Wow.exe').read_bytes(), self.original)
        self.assertEqual((self.game/'Data/a.txt').read_text(), 'original a')
        self.assertFalse((self.game/'Data/b.txt').exists())
        self.uninstall()

    def test_reverse_patch_without_executable_backup(self):
        (self.game/'Wow.exe').write_bytes(self.patched)
        self.install()
        self.uninstall()
        self.assertEqual((self.game/'Wow.exe').read_bytes(), self.original)

    def test_missing_or_corrupt_backup_aborts_before_mutation(self):
        self.install()
        backup = self.baseline/'files/Data/a.txt'
        backup.write_text('corrupted')
        with self.assertRaises(RuntimeError): self.uninstall()
        self.assertEqual((self.game/'Data/a.txt').read_text(), 'new Data/a.txt')
        backup.unlink()
        with self.assertRaises(RuntimeError): self.uninstall()
        self.assertTrue((self.game/'Data/b.txt').exists())

    def test_unknown_executable_aborts_uninstall(self):
        self.install()
        (self.game/'Wow.exe').write_bytes(b'unknown')
        with self.assertRaises(RuntimeError): self.uninstall()
        self.assertTrue((self.game/'Data/b.txt').exists())

    def test_extra_payload_rejected(self):
        (self.root/'payload/extra.txt').write_text('unlisted')
        with self.assertRaises(RuntimeError): self.install()
        self.assertEqual((self.game/'Wow.exe').read_bytes(), self.original)

    def test_bad_patch_rejected_before_payload_changes(self):
        path = self.root/'metadata/patch_manifest.json'
        data = json.loads(path.read_text()); data['patches'][0]['context_before_hex'] = '4143'
        path.write_text(json.dumps(data))
        with self.assertRaises(RuntimeError): self.install()
        self.assertEqual((self.game/'Data/a.txt').read_text(), 'original a')

    def test_explicit_path_is_authoritative(self):
        self.assertEqual(app.detect_game(self.root, str(self.game)), self.game.resolve())
        with self.assertRaises(RuntimeError): app.detect_game(self.game, str(self.game/'missing'))

    def test_invalid_patch_ranges(self):
        for offset in [-1, 6, 20]:
            with self.assertRaises(RuntimeError):
                app.patch_forward(self.original, [{'offset': offset, 'old_hex': '43', 'new_hex': '58'}])

    def test_baseline_traversal_rejected(self):
        self.install()
        path = self.baseline/'baseline.json'
        data = json.loads(path.read_text()); data['files'][0]['relative_path'] = '../outside'
        path.write_text(json.dumps(data))
        with self.assertRaises(RuntimeError): self.uninstall()
        self.assertTrue((self.game/'Data/b.txt').exists())

    def test_symlink_destination_rejected(self):
        target = self.game/'Data/a.txt'
        target.unlink()
        outside = self.game.parent/'outside'; outside.write_text('untouched')
        try: target.symlink_to(outside)
        except OSError: self.skipTest('Symlink creation unavailable')
        with self.assertRaises(RuntimeError): self.install()
        self.assertEqual(outside.read_text(), 'untouched')

    def test_modified_client_and_later_modifications_survive(self):
        variant = self.original + b'HD custom trailer'
        (self.game/'Wow.exe').write_bytes(variant)
        self.install()
        exe = self.game/'Wow.exe'
        newer = bytearray(exe.read_bytes()); newer[800] = 42
        exe.write_bytes(newer)
        self.install()  # refresh must accept another mod added after install
        self.uninstall()
        expected = bytearray(variant); expected[800] = 42
        self.assertEqual(exe.read_bytes(), expected)

    def test_missing_required_file_aborts_before_mutation(self):
        (self.game/'Data/enUS/locale-enUS.MPQ').unlink()
        with self.assertRaises(RuntimeError): self.install()
        self.assertEqual((self.game/'Data/a.txt').read_text(), 'original a')
        self.assertFalse(self.baseline.exists())

    def test_wrong_version_context_or_pe_aborts_before_mutation(self):
        for offset in (0, 132, 524, 652):
            data = bytearray(self.original); data[offset] ^= 1
            (self.game/'Wow.exe').write_bytes(data)
            with self.assertRaises(RuntimeError): self.install()
            self.assertEqual((self.game/'Data/a.txt').read_text(), 'original a')
            self.assertFalse(self.baseline.exists())

    def test_conflicting_patch_aborts_uninstall_before_mutation(self):
        self.install()
        data = bytearray(self.patched); data[522] = 0xff
        (self.game/'Wow.exe').write_bytes(data)
        with self.assertRaises(RuntimeError): self.uninstall()
        self.assertTrue((self.game/'Data/b.txt').exists())

    @unittest.skipUnless(shutil.which('powershell.exe'), 'Windows PowerShell unavailable')
    def test_windows_roundtrip_and_explicit_path(self):
        for name in ('install.ps1', 'uninstall.ps1', 'client-compatibility.ps1'):
            shutil.copy2(ROOT/name, self.root/name)
        def invoke(name, path):
            env = os.environ.copy()
            # Windows PowerShell must construct its own module search path;
            # inheriting PowerShell 7's path can hide its built-in modules.
            env = {k: v for k, v in env.items() if k.upper() != 'PSMODULEPATH'}
            return subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                   '-File', str(self.root/name), '-GamePath', str(path)],
                                  capture_output=True, text=True, timeout=30, env=env)
        for name in ('install.ps1', 'install.ps1', 'uninstall.ps1'):
            result = invoke(name, self.game)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual((self.game/'Wow.exe').read_bytes(), self.original)
        self.assertEqual((self.game/'Data/a.txt').read_text(), 'original a')
        result = invoke('install.ps1', self.game/'missing')
        self.assertNotEqual(result.returncode, 0)
        result = invoke('install.ps1', self.game)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        backup = self.baseline/'files/Data/a.txt'
        backup.unlink()
        result = invoke('uninstall.ps1', self.game)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.game/'Data/b.txt').exists())
        self.assertEqual((self.game/'Wow.exe').read_bytes(), self.patched)

    @unittest.skipUnless(shutil.which('powershell.exe'), 'Windows PowerShell unavailable')
    def test_windows_modified_client_roundtrip(self):
        for name in ('install.ps1','uninstall.ps1','client-compatibility.ps1'):
            shutil.copy2(ROOT/name, self.root/name)
        exe = self.game/'Wow.exe'
        exe.write_bytes(self.original + b'HD trailer')
        env = {k: v for k, v in os.environ.items() if k.upper() != 'PSMODULEPATH'}
        for name in ('install.ps1','install.ps1','uninstall.ps1'):
            result = subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass',
                '-File',str(self.root/name),'-GamePath',str(self.game)],
                capture_output=True,text=True,timeout=30,env=env)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            data = bytearray(exe.read_bytes()); data[800] = 42; exe.write_bytes(data)
        expected = bytearray(self.original+b'HD trailer'); expected[800] = 42
        self.assertEqual(exe.read_bytes(),expected)
