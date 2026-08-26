import sys
import shutil
from pathlib import Path

import numpy as np
import sounddevice as sd
import soundfile as sf

from PySide6.QtCore import Qt
from PySide6.QtGui import QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QProgressBar,
    QVBoxLayout,
    QWidget,
)


AUDIO_EXTENSIONS = {".wav", ".flac", ".ogg", ".aiff", ".aif"}


class AudioDatasetChecker(QMainWindow):
    def __init__(self):
        super().__init__()

        self.setWindowTitle("Audio Dataset Checker")
        self.resize(760, 430)

        self.folder = None
        self.audio_files = []
        self.index = 0
        self.last_excluded = None

        self._build_ui()
        self._setup_shortcuts()
        self._update_ui()

    def _build_ui(self):
        root = QWidget()
        self.setCentralWidget(root)

        layout = QVBoxLayout(root)
        layout.setSpacing(16)
        layout.setContentsMargins(24, 24, 24, 24)

        # Folder selection
        top = QHBoxLayout()

        self.folder_label = QLabel("フォルダ未選択")
        self.folder_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.folder_label.setWordWrap(True)

        self.select_button = QPushButton("フォルダを選択")
        self.select_button.clicked.connect(self.select_folder)

        top.addWidget(self.folder_label, 1)
        top.addWidget(self.select_button)
        layout.addLayout(top)

        # Progress
        self.progress_label = QLabel("0 / 0")
        self.progress_label.setAlignment(Qt.AlignCenter)

        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 1)
        self.progress_bar.setValue(0)

        layout.addWidget(self.progress_label)
        layout.addWidget(self.progress_bar)

        # Current file
        self.status_label = QLabel("確認するフォルダを選択してください")
        self.status_label.setAlignment(Qt.AlignCenter)
        self.status_label.setStyleSheet("font-size: 16px;")

        self.filename_label = QLabel("—")
        self.filename_label.setAlignment(Qt.AlignCenter)
        self.filename_label.setWordWrap(True)
        self.filename_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.filename_label.setStyleSheet("font-size: 20px; font-weight: 600;")

        layout.addStretch()
        layout.addWidget(self.status_label)
        layout.addWidget(self.filename_label)
        layout.addStretch()

        # Playback
        play_row = QHBoxLayout()
        self.play_button = QPushButton("▶ 再生  [Space]")
        self.stop_button = QPushButton("■ 停止")

        self.play_button.setMinimumHeight(48)
        self.stop_button.setMinimumHeight(48)

        self.play_button.clicked.connect(self.play_audio)
        self.stop_button.clicked.connect(self.stop_audio)

        play_row.addWidget(self.play_button)
        play_row.addWidget(self.stop_button)
        layout.addLayout(play_row)

        # Classification
        action_row = QHBoxLayout()

        self.keep_button = QPushButton("そのまま・次へ  [K]")
        self.exclude_button = QPushButton("除外・次へ  [X]")

        self.keep_button.setMinimumHeight(64)
        self.exclude_button.setMinimumHeight(64)

        self.keep_button.clicked.connect(self.keep_and_next)
        self.exclude_button.clicked.connect(self.exclude_and_next)

        action_row.addWidget(self.keep_button)
        action_row.addWidget(self.exclude_button)
        layout.addLayout(action_row)

        # Undo
        self.undo_button = QPushButton("直前の除外を元に戻す  [Ctrl+Z]")
        self.undo_button.clicked.connect(self.undo_last_exclusion)
        layout.addWidget(self.undo_button)

        self.info_label = QLabel(
            "除外した音声は削除せず、選択したフォルダ内の「_excluded」へ移動します。"
        )
        self.info_label.setAlignment(Qt.AlignCenter)
        self.info_label.setWordWrap(True)
        layout.addWidget(self.info_label)

    def _setup_shortcuts(self):
        self.play_shortcut = QShortcut(QKeySequence(Qt.Key_Space), self)
        self.play_shortcut.activated.connect(self.play_audio)

        self.keep_shortcut = QShortcut(QKeySequence("K"), self)
        self.keep_shortcut.activated.connect(self.keep_and_next)

        self.exclude_shortcut = QShortcut(QKeySequence("X"), self)
        self.exclude_shortcut.activated.connect(self.exclude_and_next)

        self.undo_shortcut = QShortcut(QKeySequence.Undo, self)
        self.undo_shortcut.activated.connect(self.undo_last_exclusion)

    def select_folder(self):
        selected = QFileDialog.getExistingDirectory(
            self,
            "確認する音声フォルダを選択",
        )

        if not selected:
            return

        self.stop_audio()

        self.folder = Path(selected)
        excluded_dir = self.folder / "_excluded"

        # 選択フォルダ以下を再帰検索し、階層化されたデータセットにも対応する。
        # _excluded 内の音声は再検査の対象外とする。
        self.audio_files = sorted(
            [
                p
                for p in self.folder.rglob("*")
                if p.is_file()
                and p.suffix.lower() in AUDIO_EXTENSIONS
                and excluded_dir not in p.parents
            ],
            key=lambda p: str(p.relative_to(self.folder)).lower(),
        )

        # _excluded は走査対象外
        excluded_dir.mkdir(exist_ok=True)

        self.index = 0
        self.last_excluded = None
        self.folder_label.setText(str(self.folder))
        self._update_ui()

        if not self.audio_files:
            QMessageBox.information(
                self,
                "音声ファイルなし",
                "このフォルダ以下に対応する音声ファイルがありません。\n"
                "対応形式: WAV / FLAC / OGG / AIFF",
            )

    def current_file(self):
        if 0 <= self.index < len(self.audio_files):
            return self.audio_files[self.index]
        return None

    def play_audio(self):
        path = self.current_file()
        if path is None:
            return

        try:
            self.stop_audio()
            data, samplerate = sf.read(path, dtype="float32", always_2d=False)

            # 多チャンネルでもそのまま再生可能。
            # 念のため NaN / inf を除去。
            data = np.nan_to_num(data)

            sd.play(data, samplerate)
            self.status_label.setText("再生中")
        except Exception as e:
            QMessageBox.critical(
                self,
                "再生エラー",
                f"音声を再生できませんでした。\n\n{path.name}\n\n{e}",
            )

    def stop_audio(self):
        try:
            sd.stop()
        except Exception:
            pass

        if self.current_file() is not None:
            self.status_label.setText("確認してください")

    def keep_and_next(self):
        if self.current_file() is None:
            return

        self.stop_audio()
        self.index += 1
        self._update_ui()

    def exclude_and_next(self):
        path = self.current_file()
        if path is None or self.folder is None:
            return

        self.stop_audio()

        excluded_dir = self.folder / "_excluded"
        excluded_dir.mkdir(exist_ok=True)

        # Preserve the source folder hierarchy under _excluded.
        relative_path = path.relative_to(self.folder)
        destination = excluded_dir / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)

        # 同名ファイルがある場合は上書きせず連番を付ける
        if destination.exists():
            stem = path.stem
            suffix = path.suffix
            n = 1
            while True:
                candidate = destination.parent / f"{stem}_{n}{suffix}"
                if not candidate.exists():
                    destination = candidate
                    break
                n += 1

        try:
            shutil.move(str(path), str(destination))
        except Exception as e:
            QMessageBox.critical(
                self,
                "移動エラー",
                f"除外フォルダへ移動できませんでした。\n\n{e}",
            )
            return

        # Undo用
        self.last_excluded = (path, destination, self.index)

        # 現在の項目をリストから除去する。
        # indexはそのままにすると、次のファイルが同じindexに繰り上がる。
        self.audio_files.pop(self.index)
        self._update_ui()

    def undo_last_exclusion(self):
        if self.last_excluded is None:
            return

        original, excluded, old_index = self.last_excluded

        if not excluded.exists():
            QMessageBox.warning(
                self,
                "元に戻せません",
                "除外先のファイルが見つかりません。",
            )
            self.last_excluded = None
            self._update_ui()
            return

        if original.exists():
            QMessageBox.warning(
                self,
                "元に戻せません",
                f"元の場所に同名ファイルがあります。\n\n{original.name}",
            )
            return

        self.stop_audio()

        try:
            shutil.move(str(excluded), str(original))
        except Exception as e:
            QMessageBox.critical(
                self,
                "復元エラー",
                f"元のフォルダへ戻せませんでした。\n\n{e}",
            )
            return

        insert_index = min(old_index, len(self.audio_files))
        self.audio_files.insert(insert_index, original)
        self.index = insert_index
        self.last_excluded = None
        self._update_ui()

    def _update_ui(self):
        total = len(self.audio_files)
        path = self.current_file()

        has_file = path is not None

        self.play_button.setEnabled(has_file)
        self.stop_button.setEnabled(has_file)
        self.keep_button.setEnabled(has_file)
        self.exclude_button.setEnabled(has_file)
        self.undo_button.setEnabled(self.last_excluded is not None)

        if self.folder is None:
            self.progress_bar.setRange(0, 1)
            self.progress_bar.setValue(0)
            self.progress_label.setText("0 / 0")
            self.filename_label.setText("—")
            self.status_label.setText("確認するフォルダを選択してください")
            return

        if total == 0:
            self.progress_bar.setRange(0, 1)
            self.progress_bar.setValue(1)
            self.progress_label.setText("0 / 0")
            self.filename_label.setText("—")
            self.status_label.setText("このフォルダの確認対象はありません")
            return

        if self.index >= total:
            self.progress_bar.setRange(0, total)
            self.progress_bar.setValue(total)
            self.progress_label.setText(f"{total} / {total}")
            self.filename_label.setText("確認完了")
            self.status_label.setText("このフォルダの確認が完了しました")
            return

        self.progress_bar.setRange(0, total)
        self.progress_bar.setValue(self.index + 1)
        self.progress_label.setText(f"{self.index + 1} / {total}")
        self.filename_label.setText(str(path.relative_to(self.folder)))
        self.status_label.setText("確認してください")

    def closeEvent(self, event):
        self.stop_audio()
        event.accept()


if __name__ == "__main__":
    app = QApplication(sys.argv)

    window = AudioDatasetChecker()
    window.show()

    sys.exit(app.exec())
