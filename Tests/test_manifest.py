"""Legacy unittest entry point, exercising the replacement TypeScript validator."""
import json
import subprocess
import tempfile
from pathlib import Path
import unittest

root = Path(__file__).resolve().parents[1]
class ManifestTests(unittest.TestCase):
    def setUp(self): self.data = json.loads((root / 'Developer/miniapp.example.json').read_text())
    def validate(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.json'
            path.write_text(json.dumps(data))
            return subprocess.run(['node', str(root / 'Developer/src/cli.ts'), 'validate', str(path)], capture_output=True, text=True)
    def test_example(self): self.assertEqual(self.validate(self.data).returncode, 0)
    def test_invalid_inputs(self):
        for field, value in [('schemaVersion', True), ('schemaVersion', 2), ('id', '../app'), ('name', ' '), ('url', 'http://example.com'), ('url', 'https://user:secret@example.com'), ('url', 'https://'), ('community', 'Bad slug')]:
            with self.subTest(field=field, value=value): self.assertNotEqual(self.validate({**self.data, field: value}).returncode, 0)
    def test_web_manifest(self):
        data = json.loads((root / 'Developer/Contracts/web-v1/fixtures/manifest.json').read_text())
        self.assertEqual(self.validate(data).returncode, 0)
        self.assertNotEqual(self.validate({**data, 'screens': []}).returncode, 0)
    def test_unknown_field(self): self.assertNotEqual(self.validate({**self.data, 'token':'unsupported'}).returncode, 0)

if __name__ == '__main__': unittest.main()
