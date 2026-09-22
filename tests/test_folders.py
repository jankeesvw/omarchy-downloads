"""Folder downloads on the large-directory helper path. Run with python3 -m unittest discover -s tests."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FolderDownloads(unittest.TestCase):
    def test_helper_includes_folders_without_recursing(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / 'Movie [1080p] #1'
            folder.mkdir()
            (folder / 'movie.mp4').touch()
            (Path(tmp) / 'newer.mp4').touch()
            os.utime(folder, (100, 100))
            os.utime(Path(tmp) / 'newer.mp4', (200, 200))
            data = json.loads(subprocess.check_output([ROOT / 'bin/downloads', 'list', tmp]))
            self.assertTrue(data['ok'])
            self.assertEqual([f['name'] for f in data['files']], ['newer.mp4', folder.name])
            self.assertEqual([f['isDir'] for f in data['files']], [False, True])
            self.assertEqual(data['files'][1]['path'], str(folder))

if __name__ == '__main__':
    unittest.main()
