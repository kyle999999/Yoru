import Foundation

final class ScheduleStub: URLProtocol, @unchecked Sendable {
    static var payload = Data()
    static var offline = false
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if Self.offline { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ScheduleChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let html = try String(contentsOf: root.appendingPathComponent("Fixtures/mal-week.html"), encoding: .utf8)
        let week = try WeeklySchedule.parse(html)
        for day in BroadcastDay.allCases where day != .other && day != .unknown {
            expect(!week.titles(for: day).isEmpty, "Real weekly document supplies \(day.rawValue) titles without nextRelease")
        }
        let all = week.titles(for: .other)
        expect(Set(all.map(\.id)).count == all.count, "All schedule deduplicates stable MAL identifiers")
        expect(all.allSatisfy { $0.nextRelease == nil }, "Weekly schedule never fabricates an episode timestamp")
        expect(week.titles(for: .wednesday).allSatisfy { $0.broadcast?.day == "Wednesdays" }, "Wednesday grouping uses published weekday, not title premiere date")
        expect(WeeklySchedule.decodeEntities("A &amp; B &#x2764; &#33;") == "A & B ❤ !", "Titles decode numeric and named entities")
        do { _ = try WeeklySchedule.parse("<html>Access denied</html>"); fatalError("Challenge response must not become an empty calendar") } catch is ScheduleError {}
        do { _ = try WeeklySchedule.parse(html.replacingOccurrences(of: "<div class=\"anime-header\">Wednesday</div>", with: "")); fatalError("Missing day must not become false quiet day") } catch is ScheduleError {}
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ScheduleStub.self]
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: cache) }
        let api = ScheduleAPI(session: URLSession(configuration: config), cacheFile: cache)
        ScheduleStub.payload = Data(html.utf8)
        let loaded = try await api.week()
        _ = try await api.week()
        expect(ScheduleStub.requests == 1 && !loaded.isStale, "Whole week shares one fetch and a fresh persistent cache")
        ScheduleStub.offline = true
        let offline = try await api.week(refresh: true)
        expect(offline.isStale && offline.fetchedAt == loaded.fetchedAt && offline.value.titles(for: .wednesday).count == week.titles(for: .wednesday).count, "Offline refresh preserves the real schedule with stale label and original date")
        ScheduleStub.offline = false; ScheduleStub.payload = Data("<html>Verification required</html>".utf8)
        let challenged = try await api.week(refresh: true)
        expect(challenged.isStale && !challenged.value.titles(for: .wednesday).isEmpty, "Bad upstream HTML cannot overwrite a good week with false emptiness")
        let uncached = ScheduleAPI(session: URLSession(configuration: config), cacheFile: cache.appendingPathExtension("missing"))
        do { _ = try await uncached.week(); fatalError("Invalid response without cache must fail") } catch is ScheduleError {}
        let suite = "yoru.checkin.tests." + UUID().uuidString; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = Library(defaults: defaults)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        let today = calendar.startOfDay(for: .now).addingTimeInterval(3600)
        expect(library.claimDailyPrompt(now: today), "First launch offers a daily prompt")
        expect(!library.claimDailyPrompt(now: today), "Dismissed prompt does not nag again that day")
        expect(library.checkIn(now: today, calendar: calendar), "One tap counts a day without a journal")
        expect(!library.checkIn(now: today, calendar: calendar), "Repeated taps cannot inflate check-in count")
        expect(library.activity.count == 1 && library.streak(now: today, calendar: calendar).current == 1, "Check-in creates one persistent streak day")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        expect(library.claimDailyPrompt(now: tomorrow), "A new local day offers the popup again")
        expect(library.checkIn(now: tomorrow, calendar: calendar), "Tomorrow can be checked in")
        let restored = Library(defaults: defaults)
        expect(restored.streak(now: tomorrow, calendar: calendar).current == 2, "Check-in streak survives relaunch")
        expect(restored.journals.isEmpty && restored.saved.isEmpty, "Check-in does not create fake shows or notes")
        print("All weekly schedule and daily check-in checks passed.")
    }
    static func expect(_ condition: Bool, _ label: String) { guard condition else { fatalError(label) }; print("PASS: " + label) }
}
