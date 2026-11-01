"""Build a verified, self-contained release archive from the repository."""
from pathlib import Path
import hashlib
import importlib.util
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('installer', ROOT/'linux/wow_ita_linux.py')
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)
version = (ROOT/'VERSION').read_text().strip()
app.verify_package(ROOT)
files = []
for name in ['README.md','VERSION','client-compatibility.ps1','install.cmd','refresh.cmd',
             'uninstall.cmd','install.ps1','refresh.ps1','uninstall.ps1',
             'install-linux.sh','refresh-linux.sh','uninstall-linux.sh',
             'linux/wow_ita_linux.py','metadata/patch_manifest.json','metadata/SHA256SUMS',
             'docs/audit.md','docs/provenance.md','docs/CHANGELOG.md']:
    files.append(ROOT/name)
files.extend(app.payload_files(ROOT))
out = ROOT/'dist'
out.mkdir(exist_ok=True)
archive = out/f'WoW-ITA-v{version}.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for file in sorted(files):
        name = file.relative_to(ROOT).as_posix()
        info = zipfile.ZipInfo(name, (2026,11,1,0,0,0))
        info.create_system = 3
        info.external_attr = (0o100755 if name.endswith('.sh') else 0o100644) << 16
        z.writestr(info,file.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
(archive.with_suffix('.zip.sha256')).write_text(f'{checksum}  {archive.name}\n')
print(f'{archive.name}: {len(files)} files; SHA256 {checksum}')
