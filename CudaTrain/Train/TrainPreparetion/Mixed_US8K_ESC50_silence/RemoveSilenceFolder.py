#フォルダのsilenceを別フォルダに移し替える．silence を OUT に安全に集約しました（リネーム対応）
"""
clean_folds_5fold_1p/
├── fold1/
│   └── silence/
│       └── silence_gen_white_0.wav
├── fold2/
│   └── silence/
│       └── silence_gen_white_0.wav
...
└── fold5/
    └── silence/
処理後、以下へコピーします。
UrbanSound8K_ESC50_1p/
└── silence/
    ├── fold1_silence_gen_white_0.wav
    ├── fold2_silence_gen_white_0.wav
    └── ...
"""


import shutil
from pathlib import Path

SRC = Path("../../data/clean_folds_5fold_1p")  # 元データ
OUT = Path("../../data/UrbanSound8K_ESC50_1p/silence")  # silence をまとめたい先

OUT.mkdir(parents=True, exist_ok=True)


def get_unique_path(dst_dir: Path, base_name: str) -> Path:
    """
    名前衝突を避けるため、同名ファイルが存在する場合は
    _1, _2, _3... と連番を付けて保存する関数
    """
    dst_path = dst_dir / base_name
    if not dst_path.exists():
        return dst_path

    stem = dst_path.stem
    suffix = dst_path.suffix
    idx = 1

    while True:
        new_name = f"{stem}_{idx}{suffix}"
        new_path = dst_dir / new_name
        if not new_path.exists():
            return new_path
        idx += 1


def main():
    for fold in sorted(SRC.glob("fold*")):
        silence_dir = fold / "silence"

        if not silence_dir.exists():
            continue

        for wav in silence_dir.glob("*.wav"):
            # 出力時に fold 情報を保持した名前をベースにする
            base_name = f"{fold.name}_{wav.name}"

            # 衝突回避のための一意のパスを取得
            dst_path = get_unique_path(OUT, base_name)

            shutil.copyfile(wav, dst_path)

    print("完了：silence を OUT に安全に集約しました（リネーム対応）")


if __name__ == "__main__":
    main()
