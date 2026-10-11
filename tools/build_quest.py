"""Export a Quest APK in a named worktree, with all caches and output on a data volume.

Run inside the host build-lane lease. Requires the matching Android build template
and an existing Godot editor settings file containing SDK/JDK paths.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile


def data_path(value):
    path = Path(value).resolve()
    if os.name == "nt" and path.drive.lower() == "c:":
        raise ValueError(f"Task output must be on a data volume: {path}")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--profile-root", required=True)
    parser.add_argument("--editor-settings", required=True)
    parser.add_argument("--template-source", help="Matching Android build template directory")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--expected-signer-sha256",
                        help="Require the released app's certificate fingerprint before exporting")
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    if not (project / ".git").is_file():
        raise ValueError("Export from a named Git worktree; canonical checkouts are read-only.")
    data_path(str(project))
    apk, profile = data_path(args.output), data_path(args.profile_root)
    if apk.exists():
        raise ValueError(f"Preserve existing artifacts; choose a new output: {apk}")
    apk.parent.mkdir(parents=True, exist_ok=True)
    for sub in ["Roaming/Godot", "Local", "temp", "gradle", "android", "logs"]:
        (profile / sub).mkdir(parents=True, exist_ok=True)
    settings_path = profile / "Roaming/Godot/editor_settings-4.7.tres"
    if Path(args.editor_settings).resolve() != settings_path:
        shutil.copy2(args.editor_settings, settings_path)
    settings = settings_path.read_text(encoding="utf-8")
    def setting(key):
        match = re.search(r"^" + re.escape(key) + r" = (\".*\")$", settings, re.M)
        if not match:
            raise ValueError(f"Missing editor setting {key}")
        path = Path(json.loads(match[1])).resolve()
        if not path.is_dir():
            raise ValueError(f"Dependency is missing: {path}")
        return path
    sdk = setting("export/android/android_sdk_path")
    jdk = setting("export/android/java_sdk_path")
    # Godot also injects ANDROID_HOME from editor settings. Normalize junctions
    # here so Gradle sees the same SDK path through every configuration source.
    for key, path in {"export/android/android_sdk_path": sdk,
                      "export/android/java_sdk_path": jdk}.items():
        settings = re.sub(r"^" + re.escape(key) + r" = .*?$",
                          lambda _: key + " = " + json.dumps(path.as_posix()),
                          settings, flags=re.M)
    settings_path.write_text(settings, encoding="utf-8")
    env = os.environ.copy()
    env.update(APPDATA=str(profile / "Roaming"), LOCALAPPDATA=str(profile / "Local"),
               TEMP=str(profile / "temp"), TMP=str(profile / "temp"),
               GRADLE_USER_HOME=str(profile / "gradle"), JAVA_HOME=str(jdk),
               ANDROID_HOME=str(sdk), ANDROID_SDK_ROOT=str(sdk),
               ANDROID_USER_HOME=str(profile / "android"),
               JAVA_TOOL_OPTIONS=f"-Djava.io.tmpdir={profile / 'temp'}")
    version = subprocess.check_output([args.godot, "--version"], env=env, text=True).strip()
    build_version = (project / "android/.build_version").read_text().strip()
    if not version.startswith(build_version + "."):
        raise ValueError(f"Engine/template mismatch: {version} vs {build_version}")
    template = project / "android/build"
    if not template.exists():
        if not args.template_source:
            raise ValueError("Supply --template-source for the accepted engine's Android build template.")
        shutil.copytree(args.template_source, template, ignore=shutil.ignore_patterns(".gradle", "build"))
    # Scope Gradle workers and daemons to this task, keeping other builds alive.
    properties = template / "gradle.properties"
    text = properties.read_text(encoding="utf-8")
    for key, value in {"org.gradle.daemon": "false", "org.gradle.workers.max": "4"}.items():
        text = re.sub(r"^" + re.escape(key) + r"=.*\n?", "", text, flags=re.M)
        text += f"\n{key}={value}\n"
    properties.write_text(text, encoding="utf-8")
    preset = (project / "export_presets.cfg").read_text(encoding="utf-8")
    if args.expected_signer_sha256:
        def preset_string(key):
            return json.loads(re.search(r"^" + re.escape(key) + r'=(".*")$', preset, re.M)[1])
        certificate = subprocess.run(
            [str(jdk / "bin/keytool.exe" if os.name == "nt" else jdk / "bin/keytool"),
             "-exportcert", "-keystore", preset_string("keystore/release"),
             "-alias", preset_string("keystore/release_user"),
             "-storepass:env", "TCVR_SIGNING_PASSWORD"],
            env={**env, "TCVR_SIGNING_PASSWORD": preset_string("keystore/release_password")},
            capture_output=True, check=True).stdout
        import hashlib
        actual = hashlib.sha256(certificate).hexdigest()
        expected = args.expected_signer_sha256.replace(":", "").lower()
        if actual != expected:
            raise ValueError(f"Signing certificate mismatch: {actual}; expected {expected}. "
                             "Recover the original key before updating the existing Meta app.")
    code = int(re.search(r"version/code=(\d+)", preset)[1])
    name = re.search(r'version/name="([^"]+)"', preset)[1]
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    info = project / "scripts/build_info.gd"
    info.write_text('# Generated by tools/build_quest.py from export_presets.cfg.\n'
                    'class_name BuildInfo\nextends RefCounted\n\n'
                    f'const VERSION := "{name}"\nconst CODE := {code}\nconst BUILT := "{now}"\n', encoding="utf-8")
    log_path = profile / "logs/quest-export.log"
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen([args.godot, "--headless", "--path", str(project),
                                    "--xr-mode", "off", "--export-release", "Meta Quest", str(apk)],
                                   env=env, stdout=log, stderr=subprocess.STDOUT, cwd=project)
        print(f"Export PID {process.pid}: {name} code {code}; log {log_path}", flush=True)
        try:
            result = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
            else:
                process.kill()
            raise RuntimeError("Export timed out; stopped only this export's process tree.")
    if result:
        raise RuntimeError(f"Export exited {result}; inspect {log_path}")
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("APK failed ZIP integrity check")
        required = ["AndroidManifest.xml", "lib/arm64-v8a/libgodot_android.so"]
        if any(item not in archive.namelist() for item in required):
            raise RuntimeError("APK is missing its Quest manifest/native engine")
        if not any(item.startswith("assets/") for item in archive.namelist()):
            raise RuntimeError("APK has no packaged project content")
    print(f"Quest export complete: {apk} ({apk.stat().st_size} bytes). Verify manifest and signature before upload.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Build failed: {error}", file=sys.stderr)
        sys.exit(1)
