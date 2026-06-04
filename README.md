# SignLingo

A Flutter mobile application for learning and translating Malay Sign Language (BIM) using on-device AI. All sign recognition runs fully on the device without requiring an internet connection for inference.

---

## Features

- **Sign Dictionary** — Browse BIM signs by category with reference images and YouTube tutorials
- **Guided Practice** — Real-time finger-level feedback using MediaPipe landmark detection
- **Quiz Mode** — Perform signs to answer randomly generated questions with session score tracking
- **Live Detection** — Continuous real-time sign recognition with Auto, Static, and Dynamic modes
- **Video Call** — Peer-to-peer video call with live sign language subtitle translation via WebRTC

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile Framework | Flutter (Dart) |
| Native Android | Kotlin + MediaPipe Tasks |
| AI Model | TensorFlow Lite (CNN + GRU) |
| Backend | Supabase (Auth + Database) |
| Video Call | WebRTC (flutter_webrtc) |
| Landmark Detection | MediaPipe HandLandmarker, FaceLandmarker, PoseLandmarker |

---

## How It Works

1. The camera captures frames in YUV420 format
2. Kotlin extracts 204 hand, face, and pose keypoints per frame via MediaPipe
3. A sequence of 8 consecutive frames is fed into the on-device TFLite model
4. The model predicts the sign and displays it in real time
5. In guided mode, keypoints are compared against sign profiles for finger-level feedback
6. In video calls, predicted signs are sent as text subtitles to the remote peer via a WebRTC data channel

---

## Project Structure

```
lib/
├── screens/
│   ├── live_gesture_test.dart          Live sign detection
│   ├── guided_gesture_testing.dart     Guided practice with feedback
│   ├── quiz_session_screen.dart        Quiz mode
│   ├── video_call_screen.dart          WebRTC video call
│   └── video_call_lobby.dart           Create or join a call room
├── services/
│   ├── on_device_inference.dart        TFLite inference pipeline
│   ├── guided_feedback_engine.dart     Finger scoring and feedback
│   └── camera_service.dart             Camera stream management

android/
└── app/src/main/kotlin/
    └── MainActivity.kt                 MediaPipe keypoint extraction

training/
├── 00_data_collection.py              Desktop data collection script
├── sign_profiles.py                   Build sign reference profiles
└── training.ipynb                     CNN-GRU model training notebook
```

---

## Model Architecture

```
Input: 8 x 204 keypoints
  DiscriminativeFeatureLayer   (adds 20 geometric features, output 224)
  Conv1D(64) -> BatchNorm -> MaxPool -> Dropout
  Conv1D(128) -> BatchNorm -> Dropout
  GRU(128, return_sequences=True) -> Dropout
  GRU(64, return_sequences=False) -> Dropout
  Dense(128) -> Dense(64)
  Dense(num_classes, softmax)
```

---

## Getting Started

### Prerequisites

- Flutter 3.x
- Android Studio with NDK
- Python 3.9 or above (for training scripts only)

### Install and Run

```bash
git clone https://github.com/yourusername/signlingo.git
cd signlingo
flutter pub get
flutter run
```

[Train Your Own Model](https://github.com/Mahdil-Ash7/SignLingo-Model.git)

```bash
# Step 1 — Collect sign data
python 00_data_collection.py

# Step 2 — Build sign profiles
python sign_profiles.py

# Step 3 — Train and export TFLite model
jupyter notebook training.ipynb
```

After training, copy the following files to `assets/models/`:

```
handface_pose_cnn_gru.tflite
labels.json
sign_profiles.json
```

---

## Supabase Configuration

Update your Supabase credentials in `lib/main.dart`:

```dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL',
  anonKey: 'YOUR_SUPABASE_ANON_KEY',
);
```

Required database tables: `sign`, `video_call_rooms`

---

## Acknowledgements

- MediaPipe — On-device landmark detection
- TensorFlow Lite — On-device model inference
- flutter_webrtc — WebRTC peer-to-peer video calls
- Supabase — Backend, authentication, and real-time signalling

---

## License

Developed as a Final Year Project (FYP).
