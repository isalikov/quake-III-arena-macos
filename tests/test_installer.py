"""Offline installer integration tests. No network, compilers or app installation."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

INSTALLER = Path(__file__).resolve().parents[1] / 'install.sh'

FAKE_TOOL = r'''#!/usr/bin/env python3
import os, pathlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
fixture = pathlib.Path(os.environ['FIXTURE'])
if name == 'uname':
    print('Darwin' if args == ['-s'] else 'arm64')
elif name == 'id':
    print('501')
elif name == 'sysctl':
    print('1' if args[-1] == 'hw.optional.arm64' else '2')
elif name in ('xcode-select', 'xcrun'):
    print('/fake/apple/tools')
elif name == 'curl':
    with (fixture / 'downloads').open('a') as f: f.write(args[-1] + '\n')
    if os.environ.get('FAIL_DOWNLOAD'): sys.exit(22)
    out = pathlib.Path(args[args.index('--output') + 1])
    src = fixture / ('patch.zip' if 'latest-pk3s' in args[-1] else 'pak0.pk3')
    shutil.copyfile(src, out)
    if os.environ.get('CORRUPT_DOWNLOAD'): out.write_text('<html>bad mirror</html>')
elif name == 'git':
    if args[0] == 'init':
        source = pathlib.Path(args[-1])
        (source / 'cmake').mkdir(parents=True)
        (source / 'cmake/entitlements.plist').write_text('test entitlement')
elif name == 'cmake':
    if args[0] == '--install':
        stage = pathlib.Path(args[args.index('--prefix') + 1])
        binary = stage / 'ioquake3.app/Contents/MacOS/ioquake3'
        binary.parent.mkdir(parents=True)
        binary.write_text('new app')
        binary.chmod(0o755)
        server = stage / 'ioq3ded'
        server.write_text('new server')
        server.chmod(0o755)
elif name == 'lipo':
    if os.environ.get('WRONG_ARCH'): sys.exit(1)
elif name == 'codesign':
    if os.environ.get('BAD_SIGNATURE'): sys.exit(1)
elif name == 'ditto':
    if os.environ.get('FAIL_APP_COPY') and args[-1].endswith('.app'): sys.exit(1)
    shutil.copytree(args[0], args[1], dirs_exist_ok=True)
else:
    raise RuntimeError(name)
'''


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='q3 test ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        fake = self.bin / 'fake'
        fake.write_text(FAKE_TOOL)
        fake.chmod(0o755)
        for tool in ('uname', 'id', 'sysctl', 'curl', 'git', 'cmake',
                     'xcode-select', 'xcrun', 'lipo', 'codesign', 'ditto'):
            (self.bin / tool).symlink_to(fake)
        self.fixture = self.root / 'fixture'
        self.fixture.mkdir()
        pak0 = self.fixture / 'pak0.pk3'
        with zipfile.ZipFile(pak0, 'w') as archive:
            archive.writestr('maps/q3dm1.bsp', b'fixture map')
        patch = self.fixture / 'patch.zip'
        with zipfile.ZipFile(patch, 'w') as archive:
            for folder, count in (('baseq3', 8), ('missionpack', 3)):
                for i in range(1, count + 1):
                    pk3 = self.fixture / f'{folder}{i}.pk3'
                    with zipfile.ZipFile(pk3, 'w') as inner:
                        inner.writestr('fixture.txt', f'patch {i}')
                    archive.write(pk3, f'quake3-latest-pk3s/{folder}/pak{i}.pk3')
        script = INSTALLER.read_text()
        for key, path in (('PAK0_SHA256', pak0), ('PATCH_SHA256', patch)):
            checksum = hashlib.sha256(path.read_bytes()).hexdigest()
            script = '\n'.join(f'{key}={checksum}' if line.startswith(key + '=')
                               else line for line in script.split('\n'))
        self.script = self.root / 'install.sh'
        self.script.write_text(script)
        self.install = self.root / 'installed game'
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        HOME=str(self.root / 'home'), FIXTURE=str(self.fixture),
                        Q3_INSTALL_DIR=str(self.install),
                        Q3_CACHE_DIR=str(self.root / 'cache'), TMPDIR=str(self.root))
        for key in ('Q3_PAK0', 'Q3_PAK0_URL', 'Q3_PATCH_URL', 'Q3_JOBS'):
            self.env.pop(key, None)

    def run_install(self, **overrides):
        return subprocess.run(['bash', str(self.script)], env=dict(self.env, **overrides),
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def old_install(self):
        binary = self.install / 'ioquake3.app/Contents/MacOS/ioquake3'
        binary.parent.mkdir(parents=True)
        binary.write_text('old app')
        config = self.install / 'baseq3/autoexec.cfg'
        config.parent.mkdir()
        config.write_text('my settings')
        return binary, config

    def test_complete_install_and_cached_reinstall(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list((self.install / 'baseq3').glob('*.pk3'))), 9)
        self.assertEqual(len(list((self.install / 'missionpack').glob('*.pk3'))), 3)
        config = self.install / 'baseq3/autoexec.cfg'
        config.write_text('my settings')
        result = self.run_install(FAIL_DOWNLOAD='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(config.read_text(), 'my settings')
        self.assertEqual(len((self.fixture / 'downloads').read_text().splitlines()), 2)

    def test_bad_download_does_not_replace_existing_install(self):
        binary, config = self.old_install()
        result = self.run_install(CORRUPT_DOWNLOAD='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(binary.read_text(), 'old app')
        self.assertEqual(config.read_text(), 'my settings')
        self.assertFalse((self.root / 'cache/pak0.pk3').exists())
        self.assertIn('Checksum mismatch', result.stderr)

    def test_http_error_does_not_install(self):
        result = self.run_install(FAIL_DOWNLOAD='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.install / 'ioquake3.app').exists())

    def test_missing_native_architecture_preserves_old_app(self):
        binary, _ = self.old_install()
        result = self.run_install(WRONG_ARCH='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(binary.read_text(), 'old app')

    def test_bad_signature_preserves_old_app(self):
        binary, _ = self.old_install()
        result = self.run_install(BAD_SIGNATURE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(binary.read_text(), 'old app')

    def test_app_copy_failure_restores_previous_app(self):
        binary, _ = self.old_install()
        result = self.run_install(FAIL_APP_COPY='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(binary.read_text(), 'old app')

    def test_local_pak0_needs_only_patch_download(self):
        result = self.run_install(Q3_PAK0=str(self.fixture / 'pak0.pk3'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len((self.fixture / 'downloads').read_text().splitlines()), 1)

    def test_invalid_local_pak0_fails_before_network(self):
        bad = self.fixture / 'bad.pk3'
        bad.write_text('bad file')
        result = self.run_install(Q3_PAK0=str(bad))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.fixture / 'downloads').exists())


if __name__ == '__main__':
    unittest.main()
