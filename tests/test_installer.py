import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
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
        self.original, self.patched = b'ABCDEF', b'ABXDEF'
        (self.game/'Wow.exe').write_bytes(self.original)
        for relative in ['Data/a.txt', 'Data/b.txt']:
            p = self.root/'payload'/relative
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('new '+relative)
        (self.game/'Data').mkdir()
        (self.game/'Data/a.txt').write_text('original a')
        manifest = {'format': 1, 'package_version': '1.0.0',
                    'wow_exe': {'original_sha256': digest(self.original), 'patched_sha256': digest(self.patched)},
                    'patches': [{'offset': 2, 'old_hex': '43', 'new_hex': '58'}]}
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
        data = json.loads(path.read_text()); data['patches'][0]['new_hex'] = '59'
        path.write_text(json.dumps(data))
        with self.assertRaises(RuntimeError): self.install()
        self.assertEqual((self.game/'Data/a.txt').read_text(), 'original a')

    def test_explicit_path_is_authoritative(self):
        self.assertEqual(app.detect_game(self.root, str(self.game)), self.game)
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

    @unittest.skipUnless(shutil.which('powershell.exe'), 'Windows PowerShell unavailable')
    def test_windows_roundtrip_and_explicit_path(self):
        for name in ('install.ps1', 'uninstall.ps1'):
            shutil.copy2(ROOT/name, self.root/name)
        def invoke(name, path):
            return subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                   '-File', str(self.root/name), '-GamePath', str(path)],
                                  capture_output=True, text=True, timeout=30)
        for name in ('install.ps1', 'install.ps1', 'uninstall.ps1'):
            result = invoke(name, self.game)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual((self.game/'Wow.exe').read_bytes(), self.original)
        self.assertEqual((self.game/'Data/a.txt').read_text(), 'original a')
        result = invoke('install.ps1', self.game/'missing')
        self.assertNotEqual(result.returncode, 0)
