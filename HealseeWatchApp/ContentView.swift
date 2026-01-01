import SwiftUI
import HealthKit

struct ContentView: View {
    @StateObject private var healthManager = HealthDataManager()
    @State private var isAuthorized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerSection
                metricGrid
                insightsSection
                refreshButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .task {
            await requestPermissionsAndLoad()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Healsee")
                .font(.headline)
            Text("今日の健康スナップショット")
                .font(.footnote)
                .foregroundStyle(.secondary)
            readinessScoreView(score: healthManager.readinessScore)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "歩数", value: "\(healthManager.dailySteps) 歩", footer: "今日")
            MetricCard(title: "心拍数", value: healthManager.heartRateText, footer: "安静時平均")
            MetricCard(title: "睡眠", value: healthManager.sleepDurationText, footer: "昨夜")
            MetricCard(title: "回復度", value: healthManager.recoveryText, footer: "推定")
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("改善提案")
                .font(.headline)
            ForEach(healthManager.insights, id: \.self) { insight in
                InsightRow(text: insight)
            }
        }
    }

    private var refreshButton: some View {
        Button(action: {
            Task { await requestPermissionsAndLoad() }
        }) {
            Label("最新データを取得", systemImage: "arrow.clockwise")
        }
    }

    private func readinessScoreView(score: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("リカバリー指数")
                Spacer()
                if let score {
                    Text("\(score)")
                        .font(.title2).bold()
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            ProgressView(value: Double(score ?? 0), total: 100)
                .tint(.green)
                .animation(.easeInOut, value: score)
        }
    }

    private func requestPermissionsAndLoad() async {
        if !HKHealthStore.isHealthDataAvailable() {
            return
        }
        do {
            isAuthorized = try await healthManager.requestAuthorization()
            await healthManager.refreshAllData()
        } catch {
            // 権限が得られない場合は静かに失敗し、ユーザーが再試行できるようにする
            isAuthorized = false
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let footer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .bold()
            Text(footer)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct InsightRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.footnote)
            Spacer()
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ContentView()
}
