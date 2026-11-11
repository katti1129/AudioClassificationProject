# Copyright 2019 The TensorFlow Authors. All Rights Reserved.
# Modifications Copyright 2026 AudioClassificationProject contributors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     https://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Trainable YAMNet adapted from tensorflow/models/research/audioset/yamnet.

Uses tf_keras (Keras 2), not a mixture of Keras 2 and Keras 3 layers.
The official HDF5 weights are loaded strictly by weighted-layer topology,
including the original 521-class head, before extracting the CNN backbone.
"""

import math
from pathlib import Path

import tensorflow as tf
import tf_keras as keras


SAMPLE_RATE = 16000
NUM_SAMPLES = 16000
WEIGHTS_URL = "https://storage.googleapis.com/audioset/yamnet.h5"
PRETRAINED_DIR = Path(__file__).resolve().parent / "YAMNetFeatures" / "pretrained"
BLOCKS = (
    (2, 32), (1, 64), (2, 128), (1, 128), (2, 256), (1, 256),
    (2, 512), (1, 512), (1, 512), (1, 512), (1, 512), (1, 512),
    (2, 1024), (1, 1024),
)


def waveform_layout(num_samples):
    """Match official pad_waveform; a 1-second clip produces TWO patches."""
    minimum = int((0.96 + 0.025 - 0.010) * SAMPLE_RATE)
    hop = int(0.48 * SAMPLE_RATE)
    hops = math.ceil(max(0, num_samples - minimum) / hop)
    return minimum + hops * hop, 1 + hops


@keras.utils.register_keras_serializable(package="AudioClassification")
class YAMNetLogMel(keras.layers.Layer):
    """Batched official YAMNet frontend, with no fitted statistics."""

    def __init__(self, num_samples=NUM_SAMPLES, **kwargs):
        super().__init__(**kwargs)
        self.num_samples = int(num_samples)
        self.padded_samples, self.patch_count = waveform_layout(self.num_samples)

    def call(self, waveform):
        waveform = tf.ensure_shape(waveform, (None, self.num_samples))
        waveform = tf.pad(waveform, [[0, 0], [0, self.padded_samples - self.num_samples]])
        magnitude = tf.abs(tf.signal.stft(
            waveform, frame_length=400, frame_step=160, fft_length=512,
        ))
        mel_matrix = tf.signal.linear_to_mel_weight_matrix(
            num_mel_bins=64, num_spectrogram_bins=257, sample_rate=SAMPLE_RATE,
            lower_edge_hertz=125.0, upper_edge_hertz=7500.0,
        )
        log_mel = tf.math.log(tf.matmul(magnitude, mel_matrix) + 0.001)
        patches = tf.signal.frame(log_mel, frame_length=96, frame_step=48, axis=1)
        return tf.ensure_shape(patches, (None, self.patch_count, 96, 64))

    def compute_output_shape(self, input_shape):
        return (input_shape[0], self.patch_count, 96, 64)

    def get_config(self):
        return {**super().get_config(), "num_samples": self.num_samples}


def build_pretrained_network():
    """Official MobileNet-v1 topology; names sanitized for serialization."""
    inputs = keras.Input(shape=(96, 64), name="log_mel_patch")
    x = keras.layers.Reshape((96, 64, 1))(inputs)

    def batch_norm(tensor, name):
        return keras.layers.BatchNormalization(
            name=name, center=True, scale=False, epsilon=1e-4,
        )(tensor)

    for block, (stride, filters) in enumerate(BLOCKS, 1):
        prefix = f"layer{block}_"
        if block == 1:
            x = keras.layers.Conv2D(
                filters, 3, strides=stride, padding="same", use_bias=False,
                name=prefix + "conv",
            )(x)
            x = batch_norm(x, prefix + "conv_bn")
            x = keras.layers.ReLU(name=prefix + "relu")(x)
        else:
            x = keras.layers.DepthwiseConv2D(
                3, strides=stride, padding="same", depth_multiplier=1,
                use_bias=False, name=prefix + "depthwise_conv",
            )(x)
            x = batch_norm(x, prefix + "depthwise_conv_bn")
            x = keras.layers.ReLU(name=prefix + "depthwise_conv_relu")(x)
            x = keras.layers.Conv2D(
                filters, 1, strides=1, padding="same", use_bias=False,
                name=prefix + "pointwise_conv",
            )(x)
            x = batch_norm(x, prefix + "pointwise_conv_bn")
            x = keras.layers.ReLU(name=prefix + "pointwise_conv_relu")(x)
    embedding = keras.layers.GlobalAveragePooling2D(name="embedding")(x)
    logits = keras.layers.Dense(521, use_bias=True, name="audioset_logits")(embedding)
    scores = keras.layers.Activation("sigmoid", name="audioset_scores")(logits)
    return keras.Model(inputs, scores, name="yamnet_pretrained")


def resolve_pretrained_weights(weights_path=None):
    if weights_path is not None:
        path = Path(weights_path).resolve()
        if not path.is_file():
            raise FileNotFoundError(path)
        return path
    PRETRAINED_DIR.mkdir(parents=True, exist_ok=True)
    return Path(keras.utils.get_file(
        "yamnet.h5", WEIGHTS_URL, cache_dir=str(PRETRAINED_DIR), cache_subdir="",
    ))


def build_model(num_classes, weights_path=None, *, load_pretrained=True):
    """Return waveform classifier and its separately addressable backbone.

    load_pretrained=False is ONLY for offline structural/gradient tests.
    Production training always supplies the official pretrained weights.
    """
    pretrained = build_pretrained_network()
    if load_pretrained:
        pretrained.load_weights(str(resolve_pretrained_weights(weights_path)))
    backbone = keras.Model(
        pretrained.input, pretrained.get_layer("embedding").output, name="yamnet_backbone",
    )
    backbone.trainable = False
    inputs = keras.Input(shape=(NUM_SAMPLES,), name="waveform")
    patches = YAMNetLogMel(name="yamnet_log_mel")(inputs)
    # training=False fixes BN inference behavior, but does NOT stop gradients
    # into convolution kernels when they are unfrozen in stage 2.
    embeddings = keras.layers.TimeDistributed(backbone, name="yamnet_encoder")(
        patches, training=False,
    )
    x = keras.layers.Masking(mask_value=0.0)(embeddings)
    x = keras.layers.Bidirectional(keras.layers.LSTM(64, return_sequences=True))(x)
    x = keras.layers.Bidirectional(keras.layers.LSTM(64))(x)
    x = keras.layers.Dense(64, activation="relu")(x)
    x = keras.layers.Dropout(0.5)(x)
    outputs = keras.layers.Dense(num_classes, activation="softmax")(x)
    return keras.Model(inputs, outputs, name="yamnet_lstm"), backbone


def enable_partial_fine_tuning(backbone, first_block=13):
    if not 2 <= first_block <= len(BLOCKS):
        raise ValueError("first_block must be in [2, 14]; full fine-tuning is not used here.")
    backbone.trainable = True
    prefixes = tuple(f"layer{i}_" for i in range(first_block, len(BLOCKS) + 1))
    for layer in backbone.layers:
        layer.trainable = (
            layer.name.startswith(prefixes)
            and isinstance(layer, (keras.layers.Conv2D, keras.layers.DepthwiseConv2D))
        )
    if not backbone.trainable_weights:
        raise RuntimeError("No YAMNet convolution weights were unfrozen.")
    return [layer.name for layer in backbone.layers if layer.trainable and layer.weights]


def compile_model(model, learning_rate):
    # A fresh optimizer is required after changing trainable variables.
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=learning_rate),
        loss="sparse_categorical_crossentropy", metrics=["accuracy"],
    )
