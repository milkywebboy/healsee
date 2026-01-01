# Healsee - Health monitoring and promotion App

AppleのHealth APIを使用したApple Watchアプリケーションです。  

## プロジェクト構成
- `HealseeWatchApp/` : watchOS向けのSwiftUIアプリ。`ContentView.swift` がUI、`HealthDataManager.swift`がHealthKit経由で歩数・安静時心拍数・睡眠データを取得し、回復度スコアや改善提案を生成します。

## 主要機能
- HealthKitの権限取得
- 歩数、安静時心拍数、前夜の睡眠時間を取得して表示
- 簡易的な回復度スコア（リカバリー指数）の算出
- 睡眠不足や心拍数上昇などの状況に応じた改善提案表示
