#!/usr/bin/env python3

from pathlib import Path
import argparse
import hashlib
import json
import shutil
import sys


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


def verify_package(root):
    checksum_path = root / "metadata/SHA256SUMS"

    if not checksum_path.is_file():
        raise RuntimeError("metadata/SHA256SUMS non trovato.")

    verified = 0

    for raw in checksum_path.read_text(
        encoding="utf-8",
        errors="strict"
    ).splitlines():

        if not raw.strip():
            continue

        try:
            expected, rel = raw.split("  ", 1)
        except ValueError:
            raise RuntimeError(
                f"Riga SHA256SUMS non valida: {raw}"
            )

        path = root / rel

        if not path.is_file():
            raise RuntimeError(
                f"File del pacchetto mancante: {rel}"
            )

        actual = sha256(path)

        if actual.lower() != expected.lower():
            raise RuntimeError(
                f"Checksum errato: {rel}"
            )

        verified += 1

    if verified != 26:
        raise RuntimeError(
            f"Payload inatteso: {verified} file verificati invece di 26."
        )

    return verified


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
        try:
            p = normalize_game_path(supplied)
            if is_game_dir(p):
                candidates.append(p)
        except Exception:
            pass

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


def patch_forward(data, patches):
    out = bytearray(data)

    for patch in patches:
        offset = int(patch["offset"])
        old = hex_bytes(patch["old_hex"])
        new = hex_bytes(patch["new_hex"])

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

    return sorted(
        p for p in base.rglob("*")
        if p.is_file()
    )


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
        print(
            "Backup Wow.exe originale: gia presente"
        )

    else:
        print(
            "Wow.exe era gia patchato; "
            "nessun originale da salvare."
        )

    return baseline_root


def install(root, game):
    print()
    print("== Verifica integrita pacchetto ==")

    count = verify_package(root)
    print(f"Checksum payload: PASS ({count} file)")

    manifest = load_manifest(root)

    original_hash = (
        manifest["wow_exe"]["original_sha256"]
        .lower()
    )

    patched_hash = (
        manifest["wow_exe"]["patched_sha256"]
        .lower()
    )

    patches = manifest["patches"]

    wow = game / "Wow.exe"

    print()
    print("== Verifica Wow.exe ==")

    current = sha256(wow)

    print("SHA256:")
    print(current)

    if current == original_hash:
        wow_state = "ORIGINAL"
        print("Stato: client originale compatibile")

    elif current == patched_hash:
        wow_state = "PATCHED"
        print("Stato: Wow.exe gia patchato")

    else:
        raise RuntimeError(
            "\nWow.exe non riconosciuto.\n\n"
            "Sono supportati esclusivamente:\n"
            "World of Warcraft WotLK 3.3.5a "
            "build 12340 enUS.\n\n"
            "Il file NON e stato modificato."
        )

    print()
    print("== Backup ==")

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

        original_data = wow.read_bytes()

        patched_data = patch_forward(
            original_data,
            patches,
        )

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

    original_hash = (
        manifest["wow_exe"]["original_sha256"]
        .lower()
    )

    patched_hash = (
        manifest["wow_exe"]["patched_sha256"]
        .lower()
    )

    patches = manifest["patches"]

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

    baseline = json.loads(
        baseline_json.read_text(
            encoding="utf-8"
        )
    )

    print("Baseline trovata:")
    print(baseline_root)

    print()
    print("== Ripristino file precedenti ==")

    restored = 0
    removed = 0

    for entry in baseline["files"]:
        rel = Path(entry["relative_path"])
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

    current = sha256(wow)

    if current == original_hash:
        print("Wow.exe e gia originale.")

    elif current == patched_hash:
        if wow_backup.is_file():
            if sha256(wow_backup) != original_hash:
                raise RuntimeError(
                    "Backup Wow.exe originale "
                    "con hash inatteso."
                )

            temp = game / "Wow.exe.wowita.restore.tmp"

            shutil.copy2(
                wow_backup,
                temp
            )

            if sha256(temp) != original_hash:
                temp.unlink(missing_ok=True)
                raise RuntimeError(
                    "Verifica restore Wow.exe fallita."
                )

            temp.replace(wow)

            print(
                "Wow.exe ripristinato "
                "dal backup originale."
            )

        else:
            print(
                "Backup originale non presente."
            )
            print(
                "Applico patch inversa verificata..."
            )

            restored_data = patch_reverse(
                wow.read_bytes(),
                patches,
            )

            temp = game / "Wow.exe.wowita.restore.tmp"
            temp.write_bytes(restored_data)

            if sha256(temp) != original_hash:
                temp.unlink(missing_ok=True)
                raise RuntimeError(
                    "La patch inversa non produce "
                    "il Wow.exe originale previsto."
                )

            temp.replace(wow)

            print("Patch inversa Wow.exe: PASS")

    else:
        print()
        print("ATTENZIONE:")
        print(
            "Wow.exe ha un hash sconosciuto."
        )
        print(
            "Per sicurezza NON viene modificato."
        )

    final_hash = sha256(wow)

    if final_hash == original_hash:
        print(
            "Wow.exe finale: ORIGINAL_EXPECTED"
        )

    elif final_hash == patched_hash:
        print(
            "Wow.exe finale: ancora PATCHED"
        )

    else:
        print(
            "Wow.exe finale: HASH SCONOSCIUTO"
        )

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
        f"{args.action.capitalize()} Linux v{PACKAGE_VERSION}"
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
