"""Run with: python3 -m unittest discover -s tests -v (requires zsh and jq)."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


PLUGIN = Path(__file__).resolve().parents[1]


class RegressionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="yazi-cwd-regression-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cwd = self.root / "destination\n\n"
        self.cwd.mkdir()
        (self.root / "destination").mkdir()
        self.env = os.environ.copy()
        for key in ("YAZI_ID", "YAZI_CWD_ID"):
            self.env.pop(key, None)
        self.env.update(PATH=str(self.root) + os.pathsep + self.env["PATH"],
                        TEST_CWD=str(self.cwd), TEST_ROOT=str(self.root))
        ya = self.root / "ya"
        ya.write_text("""#!/usr/bin/env python3
import json, os, pathlib, sys, time
if sys.argv[1] != 'sub':
    sys.exit(0)
topics = sys.argv[2].split(',')
if 'hey' not in topics:
    for _ in range(3):
        print('hover,0,42,' + json.dumps({'tab': 1}), flush=True)
    time.sleep(0.2)
    sys.exit(0)
marker = topics[-1]
peers = {'99': {'abilities': [marker]}, '42': {'abilities': ['get-active-cwd']}}
print('hey,0,0,' + json.dumps({'peers': peers}), flush=True)
if marker.startswith('getcwd-client-') and os.environ.get('TEST_FAIL_QUERY'):
    sys.exit(0)
if marker.startswith('getcwd-client-') and os.environ.get('TEST_RETRY'):
    counter = pathlib.Path(os.environ['TEST_ROOT']) / 'queries'
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    if count <= 2:
        sys.exit(0)
print('return-active-cwd,99,42,' + json.dumps({'cwd': os.environ['TEST_CWD']}), flush=True)
time.sleep(0.2)
""")
        ya.chmod(0o755)

    def shell(self, code, nounset=False):
        result = subprocess.run(
            ["zsh", "-fu" if nounset else "-f", "-c", code],
            cwd=PLUGIN, env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_cdy_preserves_trailing_newlines(self):
        self.shell('source ./yazi-cwd.plugin.zsh; cdy 42 || exit; '
                   '[[ $PWD == $TEST_CWD ]]')

    def test_connect_preserves_trailing_newlines(self):
        self.shell('source ./yazi-cwd.plugin.zsh; yazi-connect || exit; '
                   '[[ $PWD == $TEST_CWD && $YAZI_CWD_ID == 42 ]]')

    def test_receive_preserves_trailing_newlines(self):
        frame = self.root / "frame"
        frame.write_text(json.dumps({"cwd": str(self.cwd)}) + "\n")
        self.shell('source ./yazi-cwd.plugin.zsh; zle() { return 0; }; '
                   'exec {fd}< "$TEST_ROOT/frame"; _yazi_cwd_receive "$fd"; '
                   '[[ $PWD == $TEST_CWD ]]')

    def test_follow_preserves_trailing_newlines(self):
        result = self.shell('zsh ./follow.zsh 42')
        frames = [json.loads(line) for line in result.stdout.splitlines()[1:]]
        self.assertTrue(frames)
        self.assertTrue(all(frame["cwd"] == str(self.cwd) for frame in frames))

    def test_nounset_unpaired_and_connected(self):
        self.shell('source ./yazi-cwd.plugin.zsh; '
                   'cdy && exit 3; cd "$TEST_ROOT" || exit; '
                   'YAZI_CWD_ID=42; cdy || exit; '
                   '[[ $PWD == $TEST_CWD ]] || exit; '
                   'yazi-cwd-stop; yazi-cwd-stop; '
                   '[[ -o nounset ]]', nounset=True)

    def test_failed_hover_query_retries(self):
        self.env["TEST_RETRY"] = "1"
        result = self.shell('zsh ./follow.zsh 42')
        frames = [json.loads(line) for line in result.stdout.splitlines()[1:]]
        self.assertTrue(frames, "later same-tab hover must retry a failed query")
        self.assertEqual((self.root / "queries").read_text(), "3")
        self.assertIn("No cwd reply", result.stderr)

    def test_failed_query_does_not_change_directory_or_connection(self):
        self.env["TEST_FAIL_QUERY"] = "1"
        self.shell('source ./yazi-cwd.plugin.zsh; YAZI_CWD_ID=77; '
                   'before=$PWD; cdy 42 && exit 3; '
                   'yazi-connect && exit 4; '
                   '[[ $PWD == $before && $YAZI_CWD_ID == 77 ]]')


if __name__ == "__main__":
    unittest.main()
