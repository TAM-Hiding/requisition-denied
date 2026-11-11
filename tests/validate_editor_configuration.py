#!/usr/bin/env python3
"""Open/run/stop/close the real editor in a clean, disposable git checkout.

Requires a graphical Linux display and Godot 4.7.2. No source settings or editor
plugins are enabled in the real project. The temporary plugin drives public
EditorInterface methods, and is part of the disposable checkout's clean baseline.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
godot = os.environ.get('GODOT_BIN', 'godot')
with tempfile.TemporaryDirectory(prefix='rd-editor-config-') as directory:
    checkout = Path(directory) / 'project'
    checkout.mkdir()
    names = subprocess.check_output(
        ['git', 'ls-files', '-co', '--exclude-standard'], cwd=source, text=True).splitlines()
    for name in set(names):
        original = source / name
        if original.is_file():
            target = checkout / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, target)
    addon = checkout / 'addons' / 'configuration_cycle'
    addon.mkdir(parents=True)
    shutil.copy2(source / 'tests/editor_configuration_cycle.gd', addon / 'cycle.gd')
    (addon / 'plugin.cfg').write_text(
        '[plugin]\nname="Configuration cycle"\ndescription="Temporary validation harness"\n'
        'author="RD tests"\nversion="1.0"\nscript="cycle.gd"\n')
    config = checkout / 'project.godot'
    config.write_text(config.read_text() + '\n[editor_plugins]\n\n'
                      'enabled=PackedStringArray("res://addons/configuration_cycle/plugin.cfg")\n')
    env = dict(os.environ, XDG_CONFIG_HOME=str(Path(directory) / 'editor-settings'))
    log_parts = []
    def engine(*args):
        result = subprocess.run([godot, '--path', str(checkout), *args], env=env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=50)
        log_parts.append(result.stdout)
        if result.returncode or 'SCRIPT ERROR:' in result.stdout:
            raise RuntimeError(result.stdout)
        return result.stdout
    engine('--headless', '--editor', '--quit')
    # Normalize only the harness's additional plugin setting before its clean baseline.
    normalizer = checkout / 'normalize_cycle.gd'
    normalizer.write_text('extends SceneTree\nfunc _initialize() -> void:\n'
                          '\tquit(ProjectSettings.save())\n')
    engine('--headless', '--script', str(normalizer))
    # Import its UID too before recording the clean checkout.
    engine('--headless', '--editor', '--quit')
    subprocess.run(['git', 'init', '-q'], cwd=checkout, check=True)
    subprocess.run(['git', 'add', '.'], cwd=checkout, check=True)
    subprocess.run(['git', '-c', 'user.name=RD Tests', '-c', 'user.email=tests@example.invalid',
                    'commit', '-qm', 'Clean editor-cycle baseline'], cwd=checkout, check=True)
    before = config.read_bytes()
    assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=checkout)
    output = engine('--audio-driver', 'Dummy', '--editor')
    assert 'EDITOR_CYCLE saved=true played=true stopped=true' in output, output
    assert config.read_bytes() == before, subprocess.check_output(
        ['git', 'diff', '--', 'project.godot'], cwd=checkout, text=True)
    status = subprocess.check_output(['git', 'status', '--porcelain'], cwd=checkout, text=True)
    assert not status, status
    report = os.environ.get('RD_EDITOR_LOG')
    if report:
        Path(report).write_text('\n'.join(log_parts))
    print('Editor configuration cycle: clean checkout -> opened -> ran -> stopped -> closed; '
          'project.godot unchanged; git status clean')
