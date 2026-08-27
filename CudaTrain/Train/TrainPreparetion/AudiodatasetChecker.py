import json
import shutil
import sys
import time
from pathlib import Path

import numpy as np
import sounddevice as sd
import soundfile as sf

from PySide6.QtCore import Qt, QTimer
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
PROGRESS_FILE_NAME = ".audio_dataset_checker_progress.json"
AUDIO_LEVEL_WINDOW_SECONDS = 0.1
MIN_DBFS = -100.0


class AudioDatasetChecker(QMainWindow):
    def __init__(self):
        super().__init__()

        self.setWindowTitle("Audio Dataset Checker")
        self.resize(760, 500)

        self.folder = None
        self.audio_files = []
        self.index = 0
        self.last_excluded = None
        self.reviewed_files = set()
        self.playback_started_at = None
        self.playback_duration = 0.0
        self.playback_audio = None
        self.playback_samplerate = None
        self.overall_rms_dbfs = MIN_DBFS
        self.peak_dbfs = MIN_DBFS

        self.playback_timer = QTimer(self)
        self.playback_timer.setInterval(50)
        self.playback_timer.timeout.connect(self._update_playback_position)

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

        self.playback_position_label = QLabel("0.00 / 0.00 秒")
        self.playback_position_label.setAlignment(Qt.AlignCenter)

        self.playback_progress_bar = QProgressBar()
        self.playback_progress_bar.setRange(0, 1)
        self.playback_progress_bar.setValue(0)
        self.playback_progress_bar.setTextVisible(False)

        layout.addWidget(self.playback_position_label)
        layout.addWidget(self.playback_progress_bar)

        self.audio_level_label = QLabel(
            "音量 RMS: 現在 -- dBFS / 全体 -- dBFS / Peak -- dBFS"
        )
        self.audio_level_label.setAlignment(Qt.AlignCenter)

        self.audio_level_bar = QProgressBar()
        self.audio_level_bar.setRange(0, 1000)
        self.audio_level_bar.setValue(0)
        self.audio_level_bar.setTextVisible(False)

        layout.addWidget(self.audio_level_label)
        layout.addWidget(self.audio_level_bar)

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

        self._load_progress()

        # _excluded は走査対象外
        excluded_dir.mkdir(exist_ok=True)

        self.index = 0
        self._skip_reviewed_files()
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

    def _progress_path(self):
        if self.folder is None:
            return None
        return self.folder / PROGRESS_FILE_NAME

    def _relative_key(self, path):
        return path.relative_to(self.folder).as_posix()

    def _skip_reviewed_files(self):
        while (
            self.index < len(self.audio_files)
            and self._relative_key(self.audio_files[self.index])
            in self.reviewed_files
        ):
            self.index += 1

    def _load_progress(self):
        progress_path = self._progress_path()
        self.reviewed_files = set()

        if progress_path is None or not progress_path.exists():
            return

        try:
            progress = json.loads(progress_path.read_text(encoding="utf-8"))
            reviewed = progress.get("reviewed_files", [])
            if not isinstance(reviewed, list):
                raise ValueError("reviewed_files must be a list")
            self.reviewed_files = {
                item for item in reviewed if isinstance(item, str)
            }
        except (OSError, json.JSONDecodeError, ValueError) as e:
            QMessageBox.warning(
                self,
                "進捗の読み込みエラー",
                f"保存済みの進捗を読み込めなかったため、最初から開始します。\n\n{e}",
            )

    def _save_progress(self):
        progress_path = self._progress_path()
        if progress_path is None:
            return

        progress = {
            "version": 1,
            "reviewed_files": sorted(self.reviewed_files),
        }
        temporary_path = progress_path.with_suffix(progress_path.suffix + ".tmp")

        try:
            temporary_path.write_text(
                json.dumps(progress, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            temporary_path.replace(progress_path)
        except OSError as e:
            QMessageBox.warning(
                self,
                "進捗の保存エラー",
                f"進捗を保存できませんでした。\n\n{e}",
            )

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
            self.playback_audio = data
            self.playback_samplerate = samplerate
            self.overall_rms_dbfs = self._calculate_rms_dbfs(data)
            self.peak_dbfs = self._calculate_peak_dbfs(data)
            self.playback_duration = len(data) / samplerate
            self.playback_started_at = time.monotonic()
            self.playback_progress_bar.setRange(
                0, max(1, round(self.playback_duration * 1000))
            )
            self.playback_progress_bar.setValue(0)
            self.playback_position_label.setText(
                f"0.00 / {self.playback_duration:.2f} 秒"
            )
            self._update_audio_level(0.0)
            self.playback_timer.start()
            self.status_label.setText("再生中")
        except Exception as e:
            QMessageBox.critical(
                self,
                "再生エラー",
                f"音声を再生できませんでした。\n\n{path.name}\n\n{e}",
            )

    def stop_audio(self):
        self.playback_timer.stop()
        self.playback_started_at = None
        self.playback_duration = 0.0
        self.playback_audio = None
        self.playback_samplerate = None

        try:
            sd.stop()
        except Exception:
            pass

        self.playback_progress_bar.setRange(0, 1)
        self.playback_progress_bar.setValue(0)
        self.playback_position_label.setText("0.00 / 0.00 秒")

        if self.current_file() is not None:
            self.status_label.setText("確認してください")

    @staticmethod
    def _amplitude_to_dbfs(amplitude):
        if amplitude <= 0:
            return MIN_DBFS
        return max(MIN_DBFS, 20.0 * np.log10(amplitude))

    def _calculate_rms_dbfs(self, data):
        samples = np.asarray(data, dtype=np.float64)
        if samples.size == 0:
            return MIN_DBFS
        rms = np.sqrt(np.mean(np.square(samples)))
        return self._amplitude_to_dbfs(rms)

    def _calculate_peak_dbfs(self, data):
        samples = np.asarray(data, dtype=np.float64)
        if samples.size == 0:
            return MIN_DBFS
        return self._amplitude_to_dbfs(np.max(np.abs(samples)))

    def _update_audio_level(self, elapsed):
        if self.playback_audio is None or self.playback_samplerate is None:
            return

        window_samples = max(
            1, round(AUDIO_LEVEL_WINDOW_SECONDS * self.playback_samplerate)
        )
        start = min(
            round(elapsed * self.playback_samplerate),
            max(0, len(self.playback_audio) - window_samples),
        )
        end = min(start + window_samples, len(self.playback_audio))
        current_dbfs = self._calculate_rms_dbfs(self.playback_audio[start:end])

        self.audio_level_label.setText(
            f"音量 RMS: 現在 {current_dbfs:.1f} dBFS / "
            f"全体 {self.overall_rms_dbfs:.1f} dBFS / "
            f"Peak {self.peak_dbfs:.1f} dBFS"
        )
        level = round((current_dbfs - MIN_DBFS) / -MIN_DBFS * 1000)
        self.audio_level_bar.setValue(max(0, min(1000, level)))

    def _reset_audio_level_display(self):
        self.audio_level_label.setText(
            "音量 RMS: 現在 -- dBFS / 全体 -- dBFS / Peak -- dBFS"
        )
        self.audio_level_bar.setValue(0)

    def _update_playback_position(self):
        if self.playback_started_at is None:
            return

        elapsed = min(
            time.monotonic() - self.playback_started_at,
            self.playback_duration,
        )
        self.playback_progress_bar.setValue(round(elapsed * 1000))
        self.playback_position_label.setText(
            f"{elapsed:.2f} / {self.playback_duration:.2f} 秒"
        )
        self._update_audio_level(elapsed)

        if elapsed >= self.playback_duration:
            self.playback_timer.stop()
            self.playback_started_at = None
            if self.current_file() is not None:
                self.status_label.setText("再生完了")

    def keep_and_next(self):
        path = self.current_file()
        if path is None:
            return

        self.stop_audio()
        self.reviewed_files.add(self._relative_key(path))
        self._save_progress()
        self.index += 1
        self._skip_reviewed_files()
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
        self._save_progress()
        self._skip_reviewed_files()
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
        self._reset_audio_level_display()
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
        self._save_progress()
        event.accept()


if __name__ == "__main__":
    app = QApplication(sys.argv)

    window = AudioDatasetChecker()
    window.show()

    sys.exit(app.exec())
