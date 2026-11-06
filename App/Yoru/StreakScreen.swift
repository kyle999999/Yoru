import SwiftUI

struct StreakScreen: View {
    var library: Library
    var write: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let streak = library.streak(now: context.date)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            VStack(alignment: .leading, spacing: 12) {
                                Eyebrow(text: "YOUR DAILY GLOW")
                                Text("A little every day.\nA story that stays.").font(.system(size: 36, weight: .semibold, design: .rounded)).tracking(-1.5)
                                Text("One tap a day keeps the glow going. Stories and journals are always welcome.").font(.system(size: 13)).foregroundStyle(YoruTheme.muted)
                            }
                            glow(streak)
                            HStack(spacing: 13) {
                                metric(streak.longest, "BEST STREAK", symbol: "sparkles")
                                metric(streak.totalDays, "DAYS OF STORIES", symbol: "moon.stars")
                            }
                            VStack(alignment: .leading, spacing: 18) {
                                SectionHeading(title: "Seven little moments.", trailing: "PAST WEEK")
                                HStack(spacing: 0) {
                                    ForEach(streak.week) { day in
                                        VStack(spacing: 11) {
                                            Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.system(size: 10, weight: .medium)).foregroundStyle(YoruTheme.muted)
                                            Image(systemName: day.active ? "checkmark" : "circle.fill").font(.system(size: day.active ? 13 : 4, weight: .semibold))
                                                .foregroundStyle(day.active ? YoruTheme.ink : YoruTheme.muted)
                                                .frame(width: 34, height: 34).background(day.active ? YoruTheme.mint : .white.opacity(0.045), in: Circle())
                                        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
                                            .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)): \(day.active ? "active" : "no activity")")
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 17) {
                                SectionHeading(title: "Your constellation", trailing: "28 DAYS")
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                                    ForEach(streak.month) { day in
                                        Text(day.date.formatted(.dateTime.day())).font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .frame(maxWidth: .infinity).frame(height: 35)
                                            .foregroundStyle(day.active ? YoruTheme.ink : YoruTheme.muted)
                                            .background(day.active ? YoruTheme.violet : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                                            .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)): \(day.active ? "active" : "no activity")")
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 14) {
                                Eyebrow(text: "ONE SMALL RITUAL")
                                Text(streak.activeToday ? "You made a little space for a story today." : "A little check-in. A brighter night.").font(.system(size: 23, weight: .medium, design: .serif)).tracking(-0.5)
                                Button { withAnimation(.spring()) { _ = library.checkIn() } } label: { Label(streak.activeToday ? "Checked in for today" : "Check in for today", systemImage: streak.activeToday ? "checkmark.circle.fill" : "sparkles").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10) }.buttonStyle(.glassProminent).disabled(streak.activeToday)
                                Button(action: write) { Label("Write a journal entry", systemImage: "square.and.pencil").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10) }.buttonStyle(.glassProminent)
                                Text("Tap Check in to count today. Logging an episode or saving a new or changed journal entry also counts. No writing is required. Each local calendar day counts once. Yesterday’s streak stays active while you still have today to continue it. Backdated watch dates do not add past days.").font(.system(size: 11)).lineSpacing(4).foregroundStyle(YoruTheme.muted)
                            }.padding(21).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 26))
                        }.padding(24)
                    }
                }
            }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close daily streak") } }
        }.presentationDragIndicator(.visible).preferredColorScheme(.dark)
    }
    private func glow(_ streak: StreakSnapshot) -> some View {
        VStack(spacing: 21) {
            ZStack {
                Circle().fill(YoruTheme.violet.opacity(0.04)).frame(width: 220, height: 220).glassEffect(.regular, in: .circle)
                Circle().stroke(.white.opacity(0.06), lineWidth: 5).frame(width: 214, height: 214)
                Circle().trim(from: 0, to: streak.current == 0 ? 0 : min(1, Double(streak.current) / 7))
                    .stroke(AngularGradient(colors: [YoruTheme.violet, YoruTheme.mint, YoruTheme.violet], center: .center), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 214, height: 214).rotationEffect(.degrees(-90))
                VStack(spacing: 7) {
                    Image(systemName: streak.activeToday ? "flame.fill" : "moon.stars.fill").font(.system(size: 24, weight: .light)).foregroundStyle(YoruTheme.mint)
                    Text(String(streak.current)).font(.system(size: 70, weight: .light, design: .rounded)).tracking(-4)
                    Text("DAY STREAK").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2.7).foregroundStyle(YoruTheme.violet)
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel("Current streak: \(streak.current) days")
            Label(streak.activeToday ? "Today is glowing" : streak.current > 0 ? "Keep it glowing today" : "Your next story starts the streak", systemImage: streak.activeToday ? "checkmark.circle.fill" : "sparkle")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(streak.activeToday ? YoruTheme.mint : YoruTheme.violet)
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
    }
    private func metric(_ number: Int, _ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: symbol).foregroundStyle(YoruTheme.violet); Spacer(); Text(String(number)).font(.system(size: 27, weight: .medium, design: .rounded)) }
            Text(title).font(.system(size: 8, design: .monospaced)).tracking(1.2).foregroundStyle(YoruTheme.muted)
        }.padding(18).frame(maxWidth: .infinity).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 23))
    }
}
