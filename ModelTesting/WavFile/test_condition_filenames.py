"""モデル・音声ライブラリ不要のファイル名パーサー回帰テスト。"""
import ast
from pathlib import Path
import re
import unittest


source = Path(__file__).with_name('AllAudioClassficationTest_windowed.py')
tree = ast.parse(source.read_text(encoding='utf-8'))
# 重いモデル読み込み依存を避け、実際の定義だけを取り出して検証する。
nodes = [node for node in tree.body if
         (isinstance(node, ast.Assign) and any(
             isinstance(t, ast.Name) and t.id in {'CONDITION_TAGS', 'CONDITION_COLUMNS'}
             for t in node.targets)) or
         (isinstance(node, ast.FunctionDef) and node.name == 'parse_conditions')]
namespace = {'Path': Path, 're': re}
exec(compile(ast.Module(body=nodes, type_ignores=[]), str(source), 'exec'), namespace)
parse = namespace['parse_conditions']


class ConditionTests(unittest.TestCase):
    def test_legacy(self):
        result = parse('ambulance_CPA20m_V060_R080.wav')
        self.assertEqual((result['CPA_m'], result['Velocity_kmh'], result['Reflection']),
                         (20, 60, 0.8))
        self.assertIsNone(result['ObstacleEnabled'])

    def test_extended(self):
        result = parse('siren_PV-4.5_OBS1_N24_SEED2_DIF0_REF1_OREF0_SA-1_PA0_SPL136_SNR-5.wav')
        self.assertEqual(result['PedestrianVelocity_kmh'], -4.5)
        self.assertEqual(result['ObstacleCount'], 24)
        self.assertEqual(result['DiffractionEnabled'], 0)
        self.assertEqual(result['SNR_dB'], -5)
        self.assertIsNone(result['Velocity_kmh'])
        self.assertIsNone(result['Reflection'])

    def test_boundaries_and_unknowns(self):
        self.assertIsNone(parse('SIM_ABC_final.wav')['CPA_m'])
        self.assertIsNone(parse('siren_V060extra.wav')['Velocity_kmh'])
        self.assertEqual(parse('siren_v-30_cpa2.5m_r-020.wav')['Reflection'], -0.2)

    def test_invalid_values(self):
        for name in ['s_OBS2.wav', 's_N-1.wav', 's_SEED1.5.wav',
                     's_V30_V60.wav', 's_CPA-1m.wav']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                parse(name)


if __name__ == '__main__':
    unittest.main()
