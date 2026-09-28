# ReSpeaker / Head Poseキャリブレーション

Unity内部方位は0°=+Z正面、90°=+X右、180°=−Z後方、270°=−X左。

```text
signedDoa = invertDoa ? -rawDoa : rawDoa
localDoa = Normalize360(signedDoa + doaOffsetDeg)
localDirection = (sin(localDoa), 0, cos(localDoa))
headForward = ProjectOnPlane(head.forward, Vector3.up)
worldDirection = LookRotation(headForward, Vector3.up) * localDirection
```

初期設定 `invertDoa=true`, `doaOffsetDeg=270`：

| 生DOA | 内部方位 | 方向 |
| --- | --- | --- |
| 270 | 0 | 正面 |
| 180 | 90 | 右 |
| 90 | 180 | 後方 |
| 0 | 270 | 左 |

頭部Yaw 0°＋raw270°も、頭部Yaw +90°＋raw0°も世界正面へ向く。角度の算術平均はせず、世界方向に対応するQuaternion間の最短経路補間で平滑化する。359°/1°や180°反転でもベクトルがゼロにならない。

## 装着して合わせる

1. ヘルメットへReSpeakerを固定し、Air 2 Ultraと一緒に回る状態にする。センサーの前方マークと固定位置を記録。
2. 頭部を正面へ向け、正面のスピーカーで試験サイレンを再生する。
3. Jetson GUIまたはUnityのShow Debug Detailsで生DOAを読む。
4. UnityのAmbulance System → AmbulanceDirectionControllerのInvert DOAを仮決定し、`offset = -signedDoa`（mod 360）で正面を合わせる。
5. 右・後・左からも再生。右と左が逆ならInvertを切替え、正面のOffsetも再調整。
6. 音源を世界正面に固定したまま頭部を+90°、−90°、180°へ向ける。矢印が世界の音源方向に留まることを確認。
7. 頭部をゆっくり／速く回して遅れを確認。必要ならPose Lookback Seconds（初期0）を数十ms単位で調整。過度なDirection Smoothingを避ける。
8. Play Modeを停止後、Inspectorへ採用値を設定し、Sceneを保存してAPKを再ビルドする。Play Mode中の変更は自動保存されない。

実機では音の反射・雑音・複数音源・DOAの取得遅延によって変動する。まず単一の固定音源で方向を評価し、その後に移動・雑音条件を試す。これはシステムの動作試験手順であり、交通現場での検知性能を保証するものではない。

## Editorでの確認

完成版SceneをPlayするとEditor Simulationが初期ON。Fixed world sourceがONなら、Head Yawの操作と同時に疑似Raw DOAも逆算されるため、同じ世界方向に矢印が残る。Back→Head Yaw180°で後方の矢印が見える。

Fixed world sourceをOFFにするとRaw DOAを直接操作できる。この時は頭部相対DOAを固定するので、Yawとともに世界方向が変わるのが正しい。Webモックの「固定DOA＋カメラだけ回転」と実機の「頭部相対DOA」を混同しないこと。

Unknown、検知OFF、Stop packets、Confidence色の各スイッチも確認。実MQTTをEditorから受ける場合はEditor SimulationをOFFにし、有効なXR頭部追跡を用意する。実機追跡を偽のEditor姿勢で代替しない。

保存済みSceneのPlay Mode自動試験でYaw90°の世界方向保持とUnknown/OFF/staleを確認済み。これはマイクの装着誤差・音の反射・通信遅延を含まないため、上記の実機校正は必要。HUDは頭部基準で上0.24m・前1.4m、矢印は水平半径2.5m・下0.55mが現在の初期値。グラス装着時の視野に合わせて最終調整する。
