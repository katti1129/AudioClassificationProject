# server.py
import asyncio
import websockets
import numpy as np
import librosa
import tensorflow as tf
from tensorflow import keras
import json

# =========================
# 基本設定（学習条件と一致）
# =========================
UNITY_SR = 48000          # Unity のサンプリングレート
MODEL_SR = 16000          # 学習時のサンプリングレート
WINDOW_SEC = 1.0          # ★ 1秒入力

WIN_SAMPLES = int(MODEL_SR * WINDOW_SEC)

N_MELS = 128
N_FFT = 1024
HOP_LENGTH = 512
FMIN, FMAX = 20, 8000

# 1秒・16kHz・hop=512 → 約32 frame
TARGET_FRAMES = 32

CLASSES = ["other", "siren"]

# =========================
# モデル読み込み
# =========================
@tf.keras.utils.register_keras_serializable()
class ReduceSumLayer(tf.keras.layers.Layer):
    def __init__(self, axis=1, **kwargs):
        super().__init__(**kwargs)
        self.axis = axis

    def call(self, inputs):
        return tf.reduce_sum(inputs, axis=self.axis)

    def get_config(self):
        config = super().get_config()
        config.update({"axis": self.axis})
        return config

model = tf.keras.models.load_model("./best.keras")
model.summary()

# =========================
# WebSocket handler
# =========================
async def handler(ws):
    print("Client connected")

    try:
        async for msg in ws:
            # ---------- Unity → PCM ----------
            audio_48k = np.frombuffer(msg, dtype=np.float32)

            if len(audio_48k) == 0:
                continue

            # ---------- 48kHz → 16kHz ----------
            audio_16k = librosa.resample(
                audio_48k,
                orig_sr=UNITY_SR,
                target_sr=MODEL_SR
            )

            # ---------- 長さを1秒に固定 ----------
            if len(audio_16k) < WIN_SAMPLES:
                audio_16k = np.pad(
                    audio_16k,
                    (0, WIN_SAMPLES - len(audio_16k))
                )
            else:
                audio_16k = audio_16k[:WIN_SAMPLES]

            # ---------- Mel Spectrogram ----------
            mel = librosa.feature.melspectrogram(
                y=audio_16k,
                sr=MODEL_SR,
                n_fft=N_FFT,
                hop_length=HOP_LENGTH,
                n_mels=N_MELS,
                fmin=FMIN,
                fmax=FMAX,
                power=2.0
            )

            mel = librosa.power_to_db(mel, ref=np.max)

            # ---------- time axis を32 frameに揃える ----------
            if mel.shape[1] < TARGET_FRAMES:
                pad = TARGET_FRAMES - mel.shape[1]
                mel = np.pad(mel, ((0, 0), (0, pad)), mode="constant")
            else:
                mel = mel[:, :TARGET_FRAMES]

            # (1, 128, 32, 1)
            x = mel[np.newaxis, ..., np.newaxis]

            # ---------- 推論 ----------
            probs = model.predict(x, verbose=0)[0]
            idx = int(np.argmax(probs))

            result = {
                "label": CLASSES[idx],
                "confidence": float(probs[idx]),
                "probs": {
                    CLASSES[i]: float(probs[i])
                    for i in range(len(CLASSES))
                }
            }

            await ws.send(json.dumps(result))
            print("Send:", result)

    except websockets.ConnectionClosed:
        print("Client disconnected")

# =========================
# サーバ起動
# =========================
async def main():
    async with websockets.serve(
        handler,
        "0.0.0.0",
        8000,
        max_size=2**23
    ):
        print("Server started (ws://0.0.0.0:8000)")
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())

 