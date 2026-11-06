import SwiftUI

struct DailyCheckInScreen: View {
    var library: Library
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let streak = library.streak(now: context.date)
                    VStack(spacing: 25) {
                        Eyebrow(text: context.date.formatted(.dateTime.month(.wide).day()).uppercased())
                        ZStack {
                            Circle().fill(YoruTheme.violet.opacity(0.08)).frame(width: 150, height: 150).glassEffect(.regular, in: .circle)
                            Image(systemName: streak.activeToday ? "checkmark.seal.fill" : "moon.stars.fill")
                                .font(.system(size: 58, weight: .light)).foregroundStyle(streak.activeToday ? YoruTheme.mint : YoruTheme.violet)
                        }
                        Text(streak.activeToday ? "Today is glowing." : "A moment for you.")
                            .font(.system(size: 32, weight: .semibold, design: .rounded)).tracking(-1)
                        Text(streak.activeToday ? "You’re on a \(streak.current)-day streak. See you tomorrow." : "Tap to keep your daily glow. No episode or journal required.")
                            .font(.system(size: 15)).foregroundStyle(YoruTheme.muted).multilineTextAlignment(.center)
                        if let error = library.saveError { Text(error).font(.caption).foregroundStyle(.orange) }
                        Button {
                            if streak.activeToday { dismiss() } else { withAnimation(.spring()) { _ = library.checkIn() } }
                        } label: {
                            Label(streak.activeToday ? "Lovely. Let’s explore." : "Check in for today", systemImage: streak.activeToday ? "arrow.right" : "sparkles")
                                .font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                        }.buttonStyle(.glassProminent)
                        if !streak.activeToday { Button("Maybe later") { dismiss() }.font(.system(size: 13)).foregroundStyle(YoruTheme.muted) }
                        Text("ONE LOCAL DAY · ONE LITTLE GLOW").font(.system(size: 8, design: .monospaced)).tracking(2).foregroundStyle(YoruTheme.muted)
                    }.padding(30).frame(maxWidth: 480).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
    }
}
