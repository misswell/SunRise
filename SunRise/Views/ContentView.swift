import SwiftUI
import Combine

private let gold = Color(red: 1, green: 0.76, blue: 0.48)
private let muted = Color(red: 0.57, green: 0.65, blue: 0.73)

struct ContentView: View {
    @State private var now = Date()
    @State private var offset: Double = 0
    @State private var events: [SunriseEvent] = []
    @State private var computeTask: Task<Void, Never>?
    @State private var playing = false
    @State private var showInfo = false
    @State private var resetGlobeToken = 0
    @AppStorage("globeStyle") private var globeStyleName = GlobeStyle.realistic.rawValue
    @AppStorage("showCountries") private var showCountries = true
    @AppStorage("showCities") private var showCities = true
    private var globeStyle: GlobeStyle { GlobeStyle(rawValue: globeStyleName) ?? .realistic }
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var selectedDate: Date { now.addingTimeInterval(offset * 3600) }
    private var isLive: Bool { abs(offset) < 0.001 && !playing }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.025, green: 0.045, blue: 0.075).ignoresSafeArea()
                StarField().ignoresSafeArea().allowsHitTesting(false)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        title
                            .padding(.top, 20)
                        globe(height: min(geometry.size.width * 0.82, 350))
                            .padding(.top, 4)
                        globeControls
                            .padding(.top, 10)
                        timePanel
                            .padding(.top, 2)
                        nearby
                            .padding(.top, 28)
                        footer
                            .padding(.top, 20)
                            .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { refreshEvents() }
        .onReceive(clock) { date in
            now = date
            if playing {
                offset += 1.0 / 60.0
                if offset > 12 { offset = -12 }
            }
            if Int(date.timeIntervalSince1970) % 30 == 0 || playing && Int(date.timeIntervalSince1970) % 3 == 0 { refreshEvents() }
        }
        .onChange(of: offset) { _, _ in
            if !playing { refreshEvents() }
        }
        .sheet(isPresented: $showInfo) { infoSheet.presentationDetents([.medium]) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "sun.horizon.fill").font(.system(size: 17)).foregroundStyle(gold)
                Text("逐光").font(.system(size: 17, weight: .semibold, design: .rounded)).tracking(3)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(isLive ? Color(red: 0.6, green: 0.87, blue: 0.72) : gold).frame(width: 5, height: 5)
                Text(isLive ? "此刻 LIVE" : "时间漫游").font(.system(size: 10, weight: .semibold)).tracking(1.2)
            }.foregroundStyle(muted)
            Button { showInfo = true } label: {
                Image(systemName: "info").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    .frame(width: 30, height: 30).background(.white.opacity(0.06), in: Circle())
            }.padding(.leading, 9).accessibilityLabel("关于日出计算")
        }.padding(.top, 12)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOLLOW THE FIRST LIGHT").font(.system(size: 9, weight: .bold)).tracking(2.5).foregroundStyle(gold.opacity(0.8))
            Text("此刻，哪里\n迎来日出？")
                .font(.system(size: 32, weight: .medium, design: .rounded)).tracking(2).lineSpacing(4)
                .foregroundStyle(Color(red: 0.94, green: 0.95, blue: 0.94))
            Text("追随晨昏线，看世界慢慢苏醒")
                .font(.system(size: 12)).tracking(1.1).foregroundStyle(muted).padding(.top, 2)
        }
    }

    private func globe(height: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(red: 0.16, green: 0.37, blue: 0.55).opacity(0.17)).blur(radius: 45).padding(45)
            GlobeView(date: selectedDate, focus: events.first?.city, style: globeStyle, showCountries: showCountries, showCities: showCities, resetToken: resetGlobeToken)
            VStack {
                Spacer()
                HStack {
                    Label("晨昏交界", systemImage: "circle.lefthalf.filled")
                    Spacer()
                    Image(systemName: "hand.draw")
                    Text("拖动地球")
                }
                .font(.system(size: 10, weight: .medium)).tracking(0.8).foregroundStyle(.white.opacity(0.43))
                .padding(.horizontal, 6)
            }
        }.frame(height: height)
    }

    private var globeControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(GlobeStyle.allCases) { style in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { globeStyleName = style.rawValue }
                    } label: {
                        Text(style.rawValue).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(globeStyle == style ? Color(red: 0.08, green: 0.09, blue: 0.11) : muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(globeStyle == style ? gold : Color.white.opacity(0.06), in: Capsule())
                    }.accessibilityAddTraits(globeStyle == style ? .isSelected : [])
                }
            }
            HStack(spacing: 9) {
                overlayButton("国家边界", icon: "globe.asia.australia", isOn: $showCountries)
                overlayButton("城市", icon: "mappin.and.ellipse", isOn: $showCities)
                Spacer(minLength: 0)
                Button { resetGlobeToken += 1 } label: {
                    Label("重置视角", systemImage: "viewfinder")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(gold)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(gold.opacity(0.1), in: Capsule())
                }.accessibilityHint("恢复到当前日出城市的方向")
            }
        }
    }

    private func overlayButton(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: icon).font(.system(size: 10, weight: .medium))
                .foregroundStyle(isOn.wrappedValue ? .white : muted)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(isOn.wrappedValue ? Color.white.opacity(0.14) : Color.white.opacity(0.04), in: Capsule())
        }
        .accessibilityValue(isOn.wrappedValue ? "已显示" : "已隐藏")
    }

    private var timePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isLive ? "正在发生" : "探索时间")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(gold)
                    Text(selectedDate.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                        .font(.system(size: 12)).foregroundStyle(muted)
                }
                Spacer()
                Text(selectedDate.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                Text(TimeZone.current.abbreviation() ?? "本地")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(muted)
            }
            HStack(spacing: 12) {
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 11)).foregroundStyle(gold)
                        .frame(width: 30, height: 30).background(gold.opacity(0.12), in: Circle())
                }.accessibilityLabel(playing ? "暂停时间漫游" : "播放时间漫游")
                VStack(spacing: 3) {
                    Slider(value: $offset, in: -12...12, step: 1.0 / 60.0).tint(gold).accessibilityLabel("调整时间，前后十二小时")
                    HStack { Text("−12H"); Spacer(); Text("现在"); Spacer(); Text("+12H") }
                        .font(.system(size: 8, weight: .medium)).tracking(0.8).foregroundStyle(muted.opacity(0.8))
                }
                Button { playing = false; offset = 0; now = Date() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                        .frame(width: 28, height: 30)
                }.accessibilityLabel("回到现在")
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.09, green: 0.12, blue: 0.16).opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.075), lineWidth: 1))
    }

    private var nearby: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("正在迎接晨光").font(.system(size: 18, weight: .medium)).tracking(0.5)
                    Text("距所选时刻最近的城市日出").font(.system(size: 10)).tracking(0.4).foregroundStyle(muted)
                }
                Spacer()
                Text("SUNRISE  /  WORLDWIDE").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(gold.opacity(0.7))
            }
            if events.isEmpty {
                ProgressView().tint(gold).frame(maxWidth: .infinity, minHeight: 70)
            } else {
                ForEach(Array(events.prefix(3).enumerated()), id: \.element.id) { index, event in
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index + 1)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(gold.opacity(0.7))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.city.name).font(.system(size: 15, weight: .medium))
                            Text(event.city.country).font(.system(size: 10)).foregroundStyle(muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(event.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "zh_CN"), timeZone: TimeZone(identifier: event.city.timeZone) ?? .current)))
                                .font(.system(size: 15, weight: .medium, design: .rounded)).monospacedDigit()
                            Text(relative(event.date)).font(.system(size: 10)).foregroundStyle(gold.opacity(0.8))
                        }
                    }.padding(.vertical, 7)
                    if index < min(events.count, 3) - 1 { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkle").foregroundStyle(gold.opacity(0.65))
            Text("每一刻，都有新的日出").tracking(1)
            Spacer()
            Text("EARTH  ·  01").tracking(1.5)
        }.font(.system(size: 9)).foregroundStyle(muted.opacity(0.7))
    }

    private var infoSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("关于逐光").font(.title2.weight(.medium))
            Text("我们根据太阳位置估算昼夜交界，并从精选城市中寻找最接近所选时刻的日出。城市时间以当地时区显示。")
                .font(.body).foregroundStyle(.secondary)
            Text("日出采用太阳中心高度 −0.833° 的近似模型；地形、天气和大气条件会影响实际观测时间。地球影像为静态纹理，并非实时云图。国家边界和名称使用 Natural Earth 的示意数据，城市为精选样本。")
                .font(.footnote).foregroundStyle(.secondary)
            Text("地球纹理：Solar System Scope / Three.js，CC BY 4.0；已缩放并按日照混合。")
                .font(.caption2).foregroundStyle(.secondary)
            Link("纹理来源与许可", destination: URL(string: "https://www.solarsystemscope.com/textures/")!)
                .font(.caption2).foregroundStyle(gold)
            Spacer()
        }.padding(28).padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relative(_ date: Date) -> String {
        let minutes = Int((date.timeIntervalSince(selectedDate) / 60).rounded())
        if abs(minutes) < 1 { return "正在日出" }
        if abs(minutes) < 60 { return minutes > 0 ? "还有 \(minutes) 分钟" : "\(-minutes) 分钟前" }
        let hours = abs(minutes) / 60, rest = abs(minutes) % 60
        return minutes > 0 ? "还有 \(hours) 小时 \(rest) 分" : "\(hours) 小时 \(rest) 分前"
    }
    private func refreshEvents() {
        let date = selectedDate
        computeTask?.cancel()
        computeTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { Solar.closestEvents(to: date) }.value
            guard !Task.isCancelled else { return }
            events = result
        }
    }
}

private struct StarField: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<100 {
                let x = CGFloat((i * 197 + 47) % 997) / 997 * size.width
                let y = CGFloat((i * 337 + 109) % 991) / 991 * size.height
                let radius: CGFloat = i % 13 == 0 ? 1.1 : 0.55
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(i % 7 == 0 ? 0.3 : 0.12)))
            }
        }
    }
}
