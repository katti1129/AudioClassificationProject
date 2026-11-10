
import sys
import numpy as np
import sounddevice as sd
import soundfile as sf

from pathlib import Path
from PySide6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QFileDialog, QRadioButton,
    QButtonGroup, QSlider, QMessageBox
)
from PySide6.QtCore import Qt, QTimer


class StereoAudioPlayback(QWidget):
    def __init__(self):
        super().__init__()

        self.setWindowTitle("Stereo Audio Playback")
        self.resize(440, 320)

        self.wav_path = None
        self.audio = None
        self.fs = None
        self.position = 0
        self.stream = None

        self.output_channel = "left"
        self.gain = 0.5

        layout = QVBoxLayout(self)

        # ファイル選択
        layout.addWidget(QLabel("WAVファイル"))

        self.file_label = QLabel("未選択")
        layout.addWidget(self.file_label)

        file_button = QPushButton("ファイルを選択")
        file_button.clicked.connect(self.select_file)
        layout.addWidget(file_button)

        # 左右チャンネル選択
        layout.addWidget(QLabel("出力先"))

        channel_layout = QHBoxLayout()
        self.channel_group = QButtonGroup(self)

        for i, (label, value) in enumerate([
            ("左", "left"),
            ("右", "right"),
            ("両方", "both")
        ]):
            radio = QRadioButton(label)
            self.channel_group.addButton(radio, i)
            channel_layout.addWidget(radio)

            if value == "left":
                radio.setChecked(True)

        self.channel_group.idClicked.connect(
            self.change_channel
        )

        layout.addLayout(channel_layout)

        # 音量調整
        self.volume_label = QLabel("音量: 50%")
        layout.addWidget(self.volume_label)

        self.volume_slider = QSlider(Qt.Horizontal)
        self.volume_slider.setRange(0, 100)
        self.volume_slider.setValue(50)
        self.volume_slider.valueChanged.connect(
            self.change_volume
        )
        layout.addWidget(self.volume_slider)

        # 再生・停止ボタン
        button_layout = QHBoxLayout()

        play_button = QPushButton("再生")
        play_button.clicked.connect(self.play)

        stop_button = QPushButton("停止")
        stop_button.clicked.connect(self.stop)

        button_layout.addWidget(play_button)
        button_layout.addWidget(stop_button)
        layout.addLayout(button_layout)

        # ステータス表示
        self.status_label = QLabel("待機中")
        layout.addWidget(self.status_label)

        # 再生状態を定期確認
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.check_playback)
        self.timer.start(100)

    def select_file(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "WAVファイルを選択",
            "", "WAV Files (*.wav)"
        )

        if path:
            self.stop()
            self.wav_path = path
            self.file_label.setText(Path(path).name)
            self.status_label.setText("ファイル選択完了")

    def change_channel(self, channel_id):
        channels = {
            0: "left",
            1: "right",
            2: "both"
        }
        self.output_channel = channels[channel_id]

    def change_volume(self, value):
        self.gain = value / 100.0
        self.volume_label.setText(f"音量: {value}%")

    def audio_callback(self, outdata, frames, time, status):
        outdata.fill(0)

        remaining = len(self.audio) - self.position
        n = min(frames, remaining)

        if n > 0:
            chunk = self.audio[
                self.position:self.position + n
            ]

            chunk = np.clip(chunk * self.gain, -1, 1)

            channel = self.output_channel

            if channel in ("left", "both"):
                outdata[:n, 0] = chunk

            if channel in ("right", "both"):
                outdata[:n, 1] = chunk

            self.position += n

        if self.position >= len(self.audio):
            raise sd.CallbackStop

    def play(self):
        if not self.wav_path:
            QMessageBox.warning(
                self, "警告",
                "WAVファイルを選択してください"
            )
            return

        self.stop()

        try:
            audio, self.fs = sf.read(
                self.wav_path,
                dtype="float32",
                always_2d=True
            )

            # モノラル音声に変換
            self.audio = np.mean(audio, axis=1)

            # 最大振幅を0.9に正規化
            peak = np.max(np.abs(self.audio))

            if peak > 0:
                self.audio = self.audio / peak * 0.9

            if len(self.audio) == 0:
                raise ValueError("WAVファイルが空です")

            self.position = 0

            self.stream = sd.OutputStream(
                samplerate=self.fs,
                channels=2,
                dtype="float32",
                callback=self.audio_callback
            )

            self.stream.start()
            self.status_label.setText("再生中")

        except Exception as e:
            self.stop()
            QMessageBox.critical(
                self, "再生エラー", str(e)
            )

    def stop(self):
        if self.stream is not None:
            self.stream.abort()
            self.stream.close()
            self.stream = None

        self.status_label.setText("停止中")

    def check_playback(self):
        if self.stream is not None:
            if not self.stream.active:
                self.stream.close()
                self.stream = None
                self.status_label.setText("再生完了")

    def closeEvent(self, event):
        self.timer.stop()
        self.stop()
        event.accept()


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = StereoAudioPlayback()
    window.show()
    sys.exit(app.exec())
