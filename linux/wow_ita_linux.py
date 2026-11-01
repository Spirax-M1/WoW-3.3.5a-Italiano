#!/usr/bin/env python3

from pathlib import Path
import argparse
import hashlib
import json
import shutil
import sys
import re
import struct


PACKAGE_VERSION = "1.0.0"


def sha256(path):
    h = hashlib.sha256()

    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)

    return h.hexdigest()


def hex_bytes(value):
    return bytes.fromhex(value)


def package_root():
    return Path(__file__).resolve().parent.parent


def safe_path(root, relative):
    """Reject absolute/traversal paths and symlinks before touching client files."""
    relative = str(relative).replace('\\', '/')
    parts = relative.split('/')
    if not relative or any(p in ('', '.', '..') or ':' in p for p in parts):
        raise RuntimeError(f"Percorso non sicuro: {relative}")
    target = root
    for part in parts:
        target = target / part
        if target.is_symlink():
            raise RuntimeError(f"Link simbolico non supportato: {target}")
    if target.exists() and not target.is_file():
        raise RuntimeError(f"File atteso: {target}")
    return target


def verify_package(root):
    checksum_path = root / "metadata/SHA256SUMS"
    expected_files = set()
    for raw in checksum_path.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        match = re.fullmatch(r"([0-9a-fA-F]{64})  (payload/.+)", raw)
        if not match:
            raise RuntimeError(f"Riga SHA256SUMS non valida: {raw}")
        expected, relative = match.groups()
        path = safe_path(root, relative)
        if relative in expected_files:
            raise RuntimeError(f"Checksum duplicato: {relative}")
        expected_files.add(relative)
        if not path.is_file() or sha256(path) != expected.lower():
            raise RuntimeError(f"Checksum errato o file mancante: {relative}")
    actual_files = {p.relative_to(root).as_posix() for p in payload_files(root)}
    if not expected_files or actual_files != expected_files:
        raise RuntimeError("Elenco payload diverso dai checksum verificati.")
    return len(expected_files)


def validate_baseline(root, game):
    baseline_root = game / "WoW-ITA-Backup/v1.0.0-baseline"
    baseline_path = safe_path(game, "WoW-ITA-Backup/v1.0.0-baseline/baseline.json")
    baseline = json.loads(baseline_path.read_text(encoding="utf-8-sig"))
    if baseline.get('format') != 1 or baseline.get('package_version') != PACKAGE_VERSION:
        raise RuntimeError("Formato o versione baseline incompatibile.")
    expected = {relative_payload_path(root, p).as_posix() for p in payload_files(root)}
    found = set()
    for entry in baseline['files']:
        rel = entry['relative_path'].replace('\\', '/')
        safe_path(game, rel)
        if rel in found or type(entry.get('existed_before_install')) is not bool:
            raise RuntimeError("Baseline duplicata o non valida.")
        found.add(rel)
        if entry['existed_before_install']:
            backup = safe_path(baseline_root / 'files', rel)
            if not backup.is_file():
                raise RuntimeError(f"Backup mancante: {rel}")
            if entry.get('sha256') and sha256(backup) != entry['sha256']:
                raise RuntimeError(f"Backup corrotto: {rel}")
    if found != expected:
        raise RuntimeError("Baseline non corrispondente al payload.")
    return baseline


def load_manifest(root):
    path = root / "metadata/patch_manifest.json"

    if not path.is_file():
        raise RuntimeError(
            "metadata/patch_manifest.json non trovato."
        )

    return json.loads(
        path.read_text(encoding="utf-8")
    )


def normalize_game_path(raw):
    raw = raw.strip().strip('"').strip("'")
    return Path(raw).expanduser().resolve()


def is_game_dir(path):
    return path.is_dir() and (path / "Wow.exe").is_file()


def detect_game(root, supplied=None):
    candidates = []

    if supplied:
        p = normalize_game_path(supplied)
        if not is_game_dir(p):
            raise RuntimeError(f"Wow.exe non trovato nel percorso indicato: {p}")
        return p

    home = Path.home()

    common = [
        home / "Games/World of Warcraft 3.3.5a",
        home / "Games/WoW 3.3.5a",
        home / "World of Warcraft 3.3.5a",
        root,
        root.parent,
    ]

    for p in common:
        try:
            p = p.resolve()
        except Exception:
            continue

        if is_game_dir(p) and p not in candidates:
            candidates.append(p)

    if len(candidates) == 1:
        print("Client rilevato:")
        print(candidates[0])
        return candidates[0]

    if len(candidates) > 1:
        print("Sono stati trovati piu client:")
        print()

        for p in candidates:
            print(" ", p)

        print()

    while True:
        try:
            raw = input(
                "Inserisci la cartella del client WoW 3.3.5a: "
            )
        except EOFError:
            raise RuntimeError(
                "Percorso client non specificato."
            )

        try:
            p = normalize_game_path(raw)
        except Exception:
            print("Percorso non valido.")
            continue

        if is_game_dir(p):
            return p

        print("Wow.exe non trovato in quella cartella.")


def compatible_bytes(data, manifest, reverse=False):
    """Validate the build and every patch site before producing any output."""
    def fail():
        raise RuntimeError("Wow.exe incompatibile: richiesti PE x86 3.3.5a (12340) e istruzioni della mod intatte.")
    try:
        if data[:2] != b'MZ': fail()
        pe = struct.unpack_from('<I', data, 60)[0]
        if data[pe:pe+4] != b'PE\0\0': fail()
        machine, count = struct.unpack_from('<HH', data, pe+4)
        opt = struct.unpack_from('<H', data, pe+20)[0]
        if machine != 0x14c or struct.unpack_from('<H', data, pe+24)[0] != 0x10b: fail()
        sections = []
        version_ok = False
        version = struct.pack('<4I', 0xfeef04bd, 0x10000, 0x30003, 0x50000+12340)
        for i in range(count):
            h = pe+24+opt+i*40
            size, start = struct.unpack_from('<II', data, h+16)
            flags = struct.unpack_from('<I', data, h+36)[0]
            if start+size > len(data): fail()
            sections.append((start, start+size, flags))
            if data[h:h+8].rstrip(b'\0') == b'.rsrc' and version in data[start:start+size]:
                version_ok = True
        if not version_ok: fail()
    except (struct.error, IndexError):
        fail()
    out = bytearray(data)
    used = set()
    for patch in manifest['patches']:
        o = int(patch['offset'])
        old, new = hex_bytes(patch['old_hex']), hex_bytes(patch['new_hex'])
        before, after = hex_bytes(patch['context_before_hex']), hex_bytes(patch['context_after_hex'])
        n = len(old)
        if (not n or len(new) != n or not before or not after or o < len(before)
                or o+n+len(after) > len(data) or used.intersection(range(o,o+n))): fail()
        used.update(range(o,o+n))
        if not any(a <= o-len(before) and o+n+len(after) <= b and flags & 0x20000000
                   for a,b,flags in sections): fail()
        if data[o-len(before):o] != before or data[o+n:o+n+len(after)] != after: fail()
        if data[o:o+n] not in (old,new): fail()
        out[o:o+n] = old if reverse else new
    if not used: fail()
    return bytes(out)


def verify_required_files(game, manifest):
    for rel in manifest['required_files']:
        p = safe_path(game, rel)
        if not p.is_file() or not p.stat().st_size:
            raise RuntimeError(f"File richiesto dalla localizzazione mancante o vuoto: {rel}")


def patch_forward(data, patches):
    out = bytearray(data)

    for patch in patches:
        offset = int(patch["offset"])
        old = hex_bytes(patch["old_hex"])
        new = hex_bytes(patch["new_hex"])

        if (not old or len(old) != len(new) or offset < 0
                or offset + len(old) > len(data)):
            raise RuntimeError("Patch non valida o fuori dai limiti.")

        if len(old) != len(new):
            raise RuntimeError(
                "Patch OLD/NEW con lunghezze differenti."
            )

        current = bytes(
            out[offset:offset + len(old)]
        )

        if current != old:
            raise RuntimeError(
                f"Byte originali inattesi a offset 0x{offset:X}."
            )

        out[offset:offset + len(new)] = new

    return bytes(out)


def patch_reverse(data, patches):
    out = bytearray(data)

    for patch in patches:
        offset = int(patch["offset"])
        old = hex_bytes(patch["old_hex"])
        new = hex_bytes(patch["new_hex"])

        if (not old or len(old) != len(new) or offset < 0
                or offset + len(old) > len(data)):
            raise RuntimeError("Patch non valida o fuori dai limiti.")

        if len(old) != len(new):
            raise RuntimeError(
                "Patch OLD/NEW con lunghezze differenti."
            )

        current = bytes(
            out[offset:offset + len(new)]
        )

        if current != new:
            raise RuntimeError(
                f"Byte patched inattesi a offset 0x{offset:X}."
            )

        out[offset:offset + len(old)] = old

    return bytes(out)


def payload_files(root):
    base = root / "payload"

    paths = list(base.rglob("*"))
    if any(p.is_symlink() for p in paths) or base.is_symlink():
        raise RuntimeError("Link simbolici nel payload non supportati.")
    return sorted(p for p in paths if p.is_file())


def relative_payload_path(root, path):
    return path.relative_to(
        root / "payload"
    )


def make_baseline(root, game, wow_state, original_hash):
    backup_root = game / "WoW-ITA-Backup"
    baseline_root = (
        backup_root / "v1.0.0-baseline"
    )

    baseline_files = baseline_root / "files"
    baseline_json = baseline_root / "baseline.json"
    wow_backup = baseline_root / "Wow.exe.original"

    baseline_root.mkdir(
        parents=True,
        exist_ok=True
    )

    if not baseline_json.is_file():
        print("Creo baseline dei file preesistenti...")

        entries = []

        for src in payload_files(root):
            rel = relative_payload_path(
                root,
                src
            )

            target = game / rel
            existed = target.is_file()

            if existed:
                backup = baseline_files / rel
                backup.parent.mkdir(
                    parents=True,
                    exist_ok=True
                )

                shutil.copy2(
                    target,
                    backup
                )

            entries.append({
                "relative_path": rel.as_posix(),
                "existed_before_install": existed,
                "sha256": sha256(backup) if existed else None,
            })

        baseline = {
            "format": 1,
            "package_version": PACKAGE_VERSION,
            "files": entries,
        }

        baseline_json.write_text(
            json.dumps(
                baseline,
                indent=2,
                ensure_ascii=False,
            ) + "\n",
            encoding="utf-8",
        )

        print("Baseline payload: creata")
    else:
        validate_baseline(root, game)
        print(
            "Baseline payload: gia esistente, "
            "non viene sovrascritta"
        )

    if (
        wow_state == "ORIGINAL"
        and not wow_backup.is_file()
    ):
        shutil.copy2(
            game / "Wow.exe",
            wow_backup
        )

        if sha256(wow_backup) != original_hash:
            wow_backup.unlink(missing_ok=True)
            raise RuntimeError(
                "Verifica backup Wow.exe fallita."
            )

        print("Backup Wow.exe originale: creato")

    elif wow_backup.is_file():
        print("Backup storico Wow.exe conservato; il ripristino modifica solo le regioni della mod.")

    return baseline_root


def install(root, game):
    print()
    print("== Verifica integrita pacchetto ==")

    count = verify_package(root)
    print(f"Checksum payload: PASS ({count} file)")

    manifest = load_manifest(root)

    patches = manifest["patches"]
    wow = safe_path(game, "Wow.exe")
    verify_required_files(game, manifest)
    original_data = wow.read_bytes()
    candidate = compatible_bytes(original_data, manifest)
    original_hash = hashlib.sha256(original_data).hexdigest()
    patched_hash = hashlib.sha256(candidate).hexdigest()
    wow_state = "PATCHED" if candidate == original_data else "ORIGINAL"
    print(f"Client 3.3.5a compatibile: {wow_state}")

    print()
    print("== Backup ==")

    for source in payload_files(root):
        safe_path(game, relative_payload_path(root, source))
    for relative in ("Wow.exe", "Wow.exe.wowita.tmp",
                     "WoW-ITA-Backup/v1.0.0-baseline/baseline.json",
                     "WoW-ITA-Backup/v1.0.0-baseline/Wow.exe.original"):
        safe_path(game, relative)
    for source in payload_files(root):
        safe_path(game, "WoW-ITA-Backup/v1.0.0-baseline/files/" + relative_payload_path(root, source).as_posix())
    make_baseline(
        root,
        game,
        wow_state,
        original_hash,
    )

    print()
    print("== Installazione localizzazione ==")

    installed = 0

    for src in payload_files(root):
        rel = relative_payload_path(
            root,
            src
        )

        dst = game / rel

        dst.parent.mkdir(
            parents=True,
            exist_ok=True
        )

        shutil.copy2(src, dst)
        installed += 1

    print(f"Payload installato: {installed} file")

    if wow_state == "ORIGINAL":
        print()
        print("== Patch Wow.exe ==")

        if wow.read_bytes() != original_data:
            raise RuntimeError("Wow.exe modificato durante l'installazione.")
        patched_data = candidate

        temp = game / "Wow.exe.wowita.tmp"
        temp.write_bytes(patched_data)

        if sha256(temp) != patched_hash:
            temp.unlink(missing_ok=True)
            raise RuntimeError(
                "La patch non produce l'hash "
                "finale previsto."
            )

        temp.replace(wow)

        print("Patch Wow.exe: PASS")
    else:
        print()
        print(
            "Wow.exe gia patchato: "
            "nessuna modifica necessaria."
        )

    print()
    print("== Verifica finale ==")

    if sha256(wow) != patched_hash:
        raise RuntimeError(
            "Hash finale Wow.exe non valido."
        )

    for src in payload_files(root):
        rel = relative_payload_path(
            root,
            src
        )

        dst = game / rel

        if (
            not dst.is_file()
            or sha256(dst) != sha256(src)
        ):
            raise RuntimeError(
                f"File installato non valido: {rel}"
            )

    print("Wow.exe: PASS")
    print(f"Payload : PASS ({installed} file)")

    print()
    print("=======================================")
    print("INSTALLAZIONE COMPLETATA CON SUCCESSO")
    print("=======================================")
    print()
    print("Client:")
    print(game)


def uninstall(root, game):
    manifest = load_manifest(root)

    backup_root = game / "WoW-ITA-Backup"
    baseline_root = (
        backup_root / "v1.0.0-baseline"
    )

    baseline_files = baseline_root / "files"
    baseline_json = baseline_root / "baseline.json"
    wow_backup = baseline_root / "Wow.exe.original"

    print()
    print("== Verifica baseline ==")

    if not baseline_json.is_file():
        raise RuntimeError(
            "Baseline di installazione non trovata.\n\n"
            "Per sicurezza non vengono rimossi "
            "file alla cieca."
        )

    baseline = validate_baseline(root, game)
    safe_path(game, "Wow.exe")
    safe_path(game, "Wow.exe.wowita.restore.tmp")
    safe_path(game, "WoW-ITA-Backup/v1.0.0-baseline/Wow.exe.original")
    original_data = (game / "Wow.exe").read_bytes()
    candidate = compatible_bytes(original_data, manifest, reverse=True)

    print("Baseline trovata:")
    print(baseline_root)

    print()
    print("== Ripristino file precedenti ==")

    restored = 0
    removed = 0

    for entry in baseline["files"]:
        rel = Path(entry["relative_path"].replace("\\", "/"))
        target = game / rel

        if entry["existed_before_install"]:
            backup = baseline_files / rel

            if not backup.is_file():
                raise RuntimeError(
                    f"Backup mancante: {rel}"
                )

            target.parent.mkdir(
                parents=True,
                exist_ok=True
            )

            shutil.copy2(
                backup,
                target
            )

            restored += 1

        else:
            if target.is_file():
                target.unlink()
                removed += 1

    print("File ripristinati :", restored)
    print("File rimossi      :", removed)

    wow = game / "Wow.exe"

    print()
    print("== Ripristino Wow.exe ==")

    if wow.read_bytes() != original_data:
        raise RuntimeError("Wow.exe modificato durante la disinstallazione.")
    if candidate != original_data:
        temp = game / "Wow.exe.wowita.restore.tmp"
        temp.write_bytes(candidate)
        if temp.read_bytes() != candidate:
            raise RuntimeError("Verifica ripristino Wow.exe fallita.")
        temp.replace(wow)
    print("Regioni della mod ripristinate; altre modifiche conservate.")

    # Pulisce solo directory rimaste vuote.
    dirs = [
        game / "Interface/AddOns/QuestTradutor/Init",
        game / "Interface/AddOns/QuestTradutor/Fonts",
        game / "Interface/AddOns/QuestTradutor",
        game / "Interface/AddOns/WoWItaliano",
    ]

    for directory in dirs:
        try:
            if directory.is_dir() and not any(
                directory.iterdir()
            ):
                directory.rmdir()
        except OSError:
            pass

    print()
    print("=======================================")
    print("DISINSTALLAZIONE COMPLETATA")
    print("=======================================")
    print()
    print("Baseline conservata in:")
    print(baseline_root)


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Installer Linux/Bazzite per "
            "WoW 3.3.5a Italiano"
        )
    )

    parser.add_argument(
        "action",
        choices=[
            "install",
            "refresh",
            "uninstall",
        ],
    )

    parser.add_argument(
        "game_path",
        nargs="?",
        help=(
            "Cartella del client WoW 3.3.5a. "
            "Se omessa viene rilevata o richiesta."
        ),
    )

    args = parser.parse_args()

    root = package_root()

    print()
    print(
        "WoW 3.3.5a Italiano - "
        f"{args.action.capitalize()} Linux v{(root / 'VERSION').read_text().strip()}"
    )
    print("=" * 52)
    print()

    try:
        game = detect_game(
            root,
            args.game_path,
        )

        if args.action in (
            "install",
            "refresh",
        ):
            install(root, game)

            if args.action == "refresh":
                print()
                print("Refresh completato.")

        elif args.action == "uninstall":
            uninstall(root, game)

    except KeyboardInterrupt:
        print()
        print("Operazione annullata.")
        return 130

    except Exception as exc:
        print()
        print("ERRORE:")
        print(exc)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

