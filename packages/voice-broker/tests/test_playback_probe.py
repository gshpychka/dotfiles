import importlib.util
from pathlib import Path
import sys
import unittest

path = Path(__file__).parents[1] / "src/voice_broker/playback_probe.py"
spec = importlib.util.spec_from_file_location("metadata_probe", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
PlaybackProbe = module.PlaybackProbe

class TestProbe(unittest.TestCase):
    def rate(self, frames, interval):
        p = PlaybackProbe()
        result = None
        for i in range(101):
            r = p.report(frames, i * interval, (i + 1) * frames + 7200)
            if r is not None:
                result = r
        return result

    def test_normal_24k(self):
        self.assertEqual(self.rate(480, 20000)["reported_input_hz"], 24000)

    def test_stale_16k(self):
        self.assertEqual(self.rate(320, 20000)["reported_input_hz"], 16000)

    def test_resampled_dac_units(self):
        # 960 DAC frames at 48k become 480 input frames at 24k.
        self.assertEqual(self.rate(960 * 24000 // 48000, 20000)["reported_input_hz"], 24000)

    def test_gap_and_backwards_timestamp(self):
        p = PlaybackProbe()
        p.report(480, 100000, 10000)
        self.assertIsNone(p.report(480, 1100000, 10000))
        self.assertIsNone(p.report(480, 1000000, 10000))
        self.assertEqual(p.gaps, 2)
        self.assertEqual(p.window_frames, 0)

    def test_other_audio_contamination(self):
        p = PlaybackProbe()
        for i in range(51):
            r = p.report(480, i * 20000, 0)
        self.assertTrue(r["played_exceeds_sent"])

    def test_first_report_has_no_fake_duration(self):
        p = PlaybackProbe()
        self.assertIsNone(p.report(24000, 1000000, 24000))
        self.assertEqual(p.window_frames, 0)

if __name__ == "__main__":
    unittest.main()
