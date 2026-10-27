#!/usr/bin/env python3
"""
tools/build_release.py

Unified, deterministic release builder for ReDrive dual-target packages:
- Headunit Cockpit Launcher (com.example.redrive.headunit)
- Phone Companion (com.example.redrive.phone)

Features:
1. Target Detection (--target auto|headunit|phone|all):
   Automatically identifies affected targets based on git diff against the previous
   release commit, or explicit target selection.
2. Version Management (--bump-patch, --bump-minor, --bump-build, --set-version):
   Reads, validates, and updates pubspec.yaml version (Semantic Versioning + Android versionCode).
3. Verification Gate:
   Runs `flutter analyze` and `flutter test` (bypassable via --skip-tests for fast redrives).
4. Dual Artifact Packaging:
   Builds flavored APKs, verifies manifest badging via Android SDK `aapt`, and generates
   standardized release filenames and legacy compatibility aliases.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from typing import Dict, List, Optional, Set, Tuple

# Configuration
FLAVORS = {
    'headunit': {
        'entrypoint': 'lib/main_headunit.dart',
        'package_id': 'com.example.redrive.headunit',
        'display_name': 'Headunit Cockpit Launcher',
    },
    'phone': {
        'entrypoint': 'lib/main_phone.dart',
        'package_id': 'com.example.redrive.phone',
        'display_name': 'Phone Companion',
    },
}

HEADUNIT_PATHS = [
    'lib/widget/cockpit/',
    'lib/screens/headunit_',
    'lib/main_headunit.dart',
    'android/app/src/headunit/',
    'test/widget/pip_application_',
    'test/screens/headunit_',
    'test/headunit/',
]

PHONE_PATHS = [
    'lib/widget/companion/',
    'lib/screens/phone_',
    'lib/main_phone.dart',
    'android/app/src/phone/',
    'test/screens/phone_',
    'test/screens/companion_',
    'test/widget/companion_',
    'test/widget/parked_car_',
    'test/widget/vehicle_link_',
]

SHARED_PATHS = [
    'lib/services/',
    'lib/models/',
    'lib/providers/',
    'lib/widget/settings/',
    'lib/widget/connection/',
    'lib/screens/settings_',
    'lib/screens/connection_',
    'lib/screens/car_',
    'lib/screens/diagnostics_',
    'lib/screens/root_',
    'lib/screens/home_',
    'pubspec.yaml',
    'pubspec.lock',
    'android/app/src/main/',
    'android/build.gradle',
    'android/settings.gradle',
    'android/gradle.properties',
]


def find_repo_root() -> str:
    """Finds root of workspace where pubspec.yaml resides."""
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur != '/' and cur != '':
        if os.path.exists(os.path.join(cur, 'pubspec.yaml')):
            return cur
        cur = os.path.dirname(cur)
    return os.getcwd()


def get_changed_files(repo_root: str, base_ref: Optional[str] = None) -> List[str]:
    """Returns list of changed files from git status and diff."""
    changed: Set[str] = set()

    # 1. Unstaged / staged changes in working tree
    try:
        status_proc = subprocess.run(
            ['git', 'status', '--porcelain'],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=True,
        )
        for line in status_proc.stdout.splitlines():
            line = line.strip()
            if line and len(line) > 3:
                # Format: XY filename or XY orig -> new
                parts = line[3:].strip().split(' -> ')
                changed.add(parts[-1].strip())
    except Exception:
        pass

    # 2. Diff against base ref (or last release commit)
    if not base_ref:
        try:
            # Find the most recent release commit
            log_proc = subprocess.run(
                ['git', 'log', '--grep=chore(release)', '-n', '2', '--format=%H'],
                cwd=repo_root,
                capture_output=True,
                text=True,
                check=True,
            )
            commits = log_proc.stdout.strip().splitlines()
            if commits:
                # If current HEAD is a release commit, diff against the one before it
                head_proc = subprocess.run(
                    ['git', 'rev-parse', 'HEAD'],
                    cwd=repo_root,
                    capture_output=True,
                    text=True,
                    check=True,
                )
                head_commit = head_proc.stdout.strip()
                if commits[0] == head_commit and len(commits) > 1:
                    base_ref = commits[1]
                else:
                    base_ref = commits[0]
        except Exception:
            base_ref = 'HEAD~1'

    if base_ref:
        try:
            diff_proc = subprocess.run(
                ['git', 'diff', '--name-only', base_ref],
                cwd=repo_root,
                capture_output=True,
                text=True,
                check=True,
            )
            for path in diff_proc.stdout.splitlines():
                p = path.strip()
                if p:
                    changed.add(p)
        except Exception:
            pass

    return sorted(list(changed))


def detect_affected_targets(changed_files: List[str]) -> Tuple[List[str], str]:
    """
    Evaluates changed files to identify affected build flavors.
    Returns (affected_flavors_list, explanation_string).
    """
    if not changed_files:
        return list(FLAVORS.keys()), "No recent git changes detected; defaulting to both targets."

    has_headunit = False
    has_phone = False
    has_shared = False
    reasons: List[str] = []

    for path in changed_files:
        norm = path.replace('\\', '/')
        is_shared = any(norm.startswith(p) for p in SHARED_PATHS) or norm == 'pubspec.yaml'
        is_hu = any(norm.startswith(p) for p in HEADUNIT_PATHS)
        is_ph = any(norm.startswith(p) for p in PHONE_PATHS)

        if is_shared:
            has_shared = True
            reasons.append(f"Shared file modified: {norm}")
        elif is_hu:
            has_headunit = True
            reasons.append(f"Headunit file modified: {norm}")
        elif is_ph:
            has_phone = True
            reasons.append(f"Phone file modified: {norm}")

    if has_shared or (has_headunit and has_phone):
        return ['headunit', 'phone'], f"Both targets affected ({len(reasons)} relevant changes, e.g. {reasons[0]})"
    elif has_headunit:
        return ['headunit'], f"Headunit only ({len(reasons)} headunit changes, e.g. {reasons[0]})"
    elif has_phone:
        return ['phone'], f"Phone only ({len(reasons)} phone changes, e.g. {reasons[0]})"
    else:
        # Default to both targets if unclassified files (e.g. docs, configs)
        return ['headunit', 'phone'], "General codebase changes detected; building both targets."


def parse_pubspec_version(pubspec_path: str) -> Tuple[str, int, str]:
    """Parses versionName, versionCode, and full version string from pubspec.yaml."""
    with open(pubspec_path, 'r', encoding='utf-8') as f:
        content = f.read()

    match = re.search(r'^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)', content, re.MULTILINE)
    if not match:
        raise ValueError(f"Could not parse valid version pattern (X.Y.Z+B) from {pubspec_path}")

    major, minor, patch, code = match.groups()
    version_name = f"{major}.{minor}.{patch}"
    version_code = int(code)
    full_version = f"{version_name}+{version_code}"
    return version_name, version_code, full_version


def update_pubspec_version(pubspec_path: str, new_version_str: str) -> None:
    """Updates version line in pubspec.yaml."""
    with open(pubspec_path, 'r', encoding='utf-8') as f:
        content = f.read()

    new_content, count = re.subn(
        r'^version:\s*[^\s\n]+',
        f"version: {new_version_str}",
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if count == 0:
        raise ValueError(f"Failed to replace version in {pubspec_path}")

    with open(pubspec_path, 'w', encoding='utf-8') as f:
        f.write(new_content)


def bump_version(current_ver: str, bump_type: str) -> str:
    """Computes bumped version string."""
    name, code_str = current_ver.split('+')
    major, minor, patch = map(int, name.split('.'))
    code = int(code_str)

    if bump_type == 'patch':
        patch += 1
        code += 1
    elif bump_type == 'minor':
        minor += 1
        patch = 0
        code += 1
    elif bump_type == 'major':
        major += 1
        minor = 0
        patch = 0
        code += 1
    elif bump_type == 'build':
        code += 1
    else:
        raise ValueError(f"Unknown bump type: {bump_type}")

    return f"{major}.{minor}.{patch}+{code}"


def locate_aapt() -> Optional[str]:
    """Locates Android aapt binary across known SDK locations."""
    # 1. ANDROID_HOME or ANDROID_SDK_ROOT
    sdk_roots = [
        os.environ.get('ANDROID_HOME', ''),
        os.environ.get('ANDROID_SDK_ROOT', ''),
        '/home/usr/Documents/repos/android-toolchain/android-sdk',
    ]
    for root in sdk_roots:
        if root and os.path.isdir(root):
            candidates = sorted(glob.glob(os.path.join(root, 'build-tools', '*', 'aapt')), reverse=True)
            if candidates:
                return candidates[0]

    # 2. PATH
    which_aapt = shutil.which('aapt')
    if which_aapt:
        return which_aapt

    return None


def verify_apk_badging(aapt_path: str, apk_path: str, expected_pkg: str, expected_vn: str, expected_vc: int) -> bool:
    """Inspects APK metadata using aapt dump badging."""
    try:
        proc = subprocess.run(
            [aapt_path, 'dump', 'badging', apk_path],
            capture_output=True,
            text=True,
            check=True,
        )
        first_line = proc.stdout.splitlines()[0] if proc.stdout else ''
        # e.g.: package: name='com.example.redrive.headunit' versionCode='9' versionName='2.0.2'
        name_match = re.search(r"name='([^']+)'", first_line)
        vc_match = re.search(r"versionCode='([^']+)'", first_line)
        vn_match = re.search(r"versionName='([^']+)'", first_line)

        actual_pkg = name_match.group(1) if name_match else None
        actual_vc = int(vc_match.group(1)) if vc_match else None
        actual_vn = vn_match.group(1) if vn_match else None

        if actual_pkg != expected_pkg:
            print(f"❌ Error: Package ID mismatch: expected {expected_pkg}, got {actual_pkg}")
            return False
        if actual_vc != expected_vc:
            print(f"❌ Error: versionCode mismatch: expected {expected_vc}, got {actual_vc}")
            return False
        if actual_vn != expected_vn:
            print(f"❌ Error: versionName mismatch: expected {expected_vn}, got {actual_vn}")
            return False

        return True
    except Exception as e:
        print(f"⚠️ Warning: aapt verification failed to inspect APK: {e}")
        return False


def compute_sha256(file_path: str) -> str:
    """Computes SHA-256 hash of a file."""
    h = hashlib.sha256()
    with open(file_path, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def format_bytes(size: int) -> str:
    """Formats bytes into human readable string."""
    if size < 1024:
        return f"{size} B"
    elif size < 1024 * 1024:
        return f"{size / 1024:.1f} KB"
    else:
        return f"{size / (1024 * 1024):.1f} MB"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Deterministic ReDrive dual-target release builder for Headunit and Phone companion."
    )
    parser.add_argument(
        '--target', '-t',
        choices=['auto', 'headunit', 'phone', 'all'],
        default='auto',
        help="Target flavor to build (default: auto detects based on git diff).",
    )
    parser.add_argument(
        '--bump-patch',
        action='store_true',
        help="Increment patch version (e.g. 2.0.2+9 -> 2.0.3+10).",
    )
    parser.add_argument(
        '--bump-minor',
        action='store_true',
        help="Increment minor version (e.g. 2.0.2+9 -> 2.1.0+10).",
    )
    parser.add_argument(
        '--bump-build',
        action='store_true',
        help="Increment only build number (e.g. 2.0.2+9 -> 2.0.2+10).",
    )
    parser.add_argument(
        '--set-version',
        type=str,
        help="Explicitly set version string in pubspec.yaml (e.g. '2.1.0+11').",
    )
    parser.add_argument(
        '--skip-tests',
        action='store_true',
        help="Skip verification gate (flutter analyze and flutter test).",
    )
    parser.add_argument(
        '--base',
        type=str,
        default=None,
        help="Base git ref for diffing (default: last release commit).",
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help="Preview build decisions and versioning without modifying files or building APKs.",
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help="Output machine-readable JSON summary.",
    )

    args = parser.parse_args()
    repo_root = find_repo_root()
    pubspec_path = os.path.join(repo_root, 'pubspec.yaml')

    print("═══════════════════════════════════════════════════════════════════")
    print(" 🚗 ReDrive Release Builder & Verification Pipeline")
    print("═══════════════════════════════════════════════════════════════════")

    # 1. Version Handling
    v_name, v_code, full_version = parse_pubspec_version(pubspec_path)
    print(f"📦 Current pubspec.yaml version: {full_version} (name: {v_name}, code: {v_code})")

    target_version = full_version
    if args.set_version:
        target_version = args.set_version
    elif args.bump_patch:
        target_version = bump_version(full_version, 'patch')
    elif args.bump_minor:
        target_version = bump_version(full_version, 'minor')
    elif args.bump_build:
        target_version = bump_version(full_version, 'build')

    if target_version != full_version:
        print(f"🚀 Version bumped to: {target_version}")
        if not args.dry_run:
            update_pubspec_version(pubspec_path, target_version)
            v_name, v_code, full_version = parse_pubspec_version(pubspec_path)
    else:
        print(f"ℹ️ Retaining version: {full_version}")

    # 2. Target Selection
    changed_files = get_changed_files(repo_root, base_ref=args.base)
    if args.target == 'auto':
        targets, explanation = detect_affected_targets(changed_files)
        print(f"🎯 Target Auto-Detection: {', '.join(targets)}")
        print(f"   ↳ {explanation}")
    elif args.target == 'all':
        targets = ['headunit', 'phone']
        print(f"🎯 Target Override: all ({', '.join(targets)})")
    else:
        targets = [args.target]
        print(f"🎯 Target Override: {args.target}")

    # 3. Dry-Run early exit
    if args.dry_run:
        print("\n🔍 DRY-RUN MODE ACTIVATED:")
        print(f"   - Target Version: {target_version}")
        print(f"   - Selected Flavors: {', '.join(targets)}")
        print(f"   - Skip Tests: {args.skip_tests}")
        print(f"   - Changed Files Analyzed: {len(changed_files)}")
        print("✅ Dry run completed successfully. No files modified.")
        return 0

    # 4. Verification Gate
    if not args.skip_tests:
        print("\n── Verification Gate: flutter analyze & flutter test ─────────────")
        print("⏳ Running flutter analyze...")
        analyze_res = subprocess.run(['flutter', 'analyze'], cwd=repo_root)
        if analyze_res.returncode != 0:
            print("❌ Build halted: flutter analyze failed.")
            return analyze_res.returncode

        print("⏳ Running flutter test...")
        test_res = subprocess.run(['flutter', 'test'], cwd=repo_root)
        if test_res.returncode != 0:
            print("❌ Build halted: flutter test failed.")
            return test_res.returncode
        print("✅ Verification Gate passed: 0 analyzer issues, 100% tests passed.")
    else:
        print("\n⚠️ Warning: Verification Gate skipped via --skip-tests.")

    # 5. Build Flavors
    aapt_path = locate_aapt()
    built_artifacts: List[Dict[str, str]] = []
    output_dir = os.path.join(repo_root, 'build', 'app', 'outputs', 'flutter-apk')
    os.makedirs(output_dir, exist_ok=True)

    for target in targets:
        cfg = FLAVORS[target]
        entrypoint = cfg['entrypoint']
        pkg_id = cfg['package_id']
        display_name = cfg['display_name']

        print(f"\n── Building Flavor: {target} ({display_name}) ────────────")
        cmd = [
            'flutter', 'build', 'apk',
            '--flavor', target,
            '-t', entrypoint,
        ]
        print(f"⚙️ Executing: {' '.join(cmd)}")
        build_proc = subprocess.run(cmd, cwd=repo_root)
        if build_proc.returncode != 0:
            print(f"❌ Build failed for flavor: {target}")
            return build_proc.returncode

        # Default flutter build path
        default_apk = os.path.join(output_dir, f"app-{target}-release.apk")
        if not os.path.exists(default_apk):
            print(f"❌ Build artifact not found: {default_apk}")
            return 1

        # Binary badging verification
        if aapt_path and os.path.exists(aapt_path):
            print(f"🔎 Verifying manifest badging via aapt ({os.path.basename(aapt_path)})...")
            is_valid = verify_apk_badging(aapt_path, default_apk, pkg_id, v_name, v_code)
            if not is_valid:
                print(f"❌ APK badging validation failed for {target}!")
                return 1
            print(f"   ✓ Badging confirmed: {pkg_id} v{v_name} ({v_code})")
        else:
            print("⚠️ Notice: aapt not found; skipping binary badging check.")

        # Standard release names & backwards compatibility aliases
        primary_name = f"redrive-{target}-v{full_version}-release.apk"
        legacy_name = f"obdrive-{target}-v{full_version}-release.apk"

        primary_path = os.path.join(output_dir, primary_name)
        legacy_path = os.path.join(output_dir, legacy_name)

        shutil.copyfile(default_apk, primary_path)
        shutil.copyfile(default_apk, legacy_path)

        size_bytes = os.path.getsize(primary_path)
        sha256_hash = compute_sha256(primary_path)

        built_artifacts.append({
            'target': target,
            'package_id': pkg_id,
            'file_name': primary_name,
            'file_path': primary_path,
            'legacy_name': legacy_name,
            'size_bytes': size_bytes,
            'size_formatted': format_bytes(size_bytes),
            'sha256': sha256_hash,
        })
        print(f"✅ Generated: {primary_name} ({format_bytes(size_bytes)})")

    # 6. Summary Output
    print("\n═══════════════════════════════════════════════════════════════════")
    print(f" 🎉 Build Completed Successfully (v{full_version})")
    print("═══════════════════════════════════════════════════════════════════")
    for art in built_artifacts:
        print(f"• Target:   {art['target']} ({art['package_id']})")
        print(f"  Artifact: {art['file_name']} ({art['size_formatted']})")
        print(f"  Path:     {art['file_path']}")
        print(f"  SHA-256:  {art['sha256']}")
        print()

    if args.json:
        result_payload = {
            'status': 'success',
            'version': full_version,
            'version_name': v_name,
            'version_code': v_code,
            'targets': targets,
            'artifacts': built_artifacts,
        }
        print("── JSON Output ──")
        print(json.dumps(result_payload, indent=2))

    print("Next step for agents:")
    print(f"git add pubspec.yaml && git commit -m \"chore(release): bump version to {full_version} for {', '.join(targets)} packages [M5]\"")
    return 0


if __name__ == '__main__':
    sys.exit(main())
