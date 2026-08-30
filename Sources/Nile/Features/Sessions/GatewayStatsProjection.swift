import Foundation

struct ActivityMomentum: Equatable, Sendable {
    let currentStreak: Int
    let longestStreak: Int
    let activeDays: Int
    let weeklySessions: Int64
    let weeklyCalls: Int64
    let bestDaySessions: Int64
}

extension GatewayStats {
    func activityMomentum(today: Date = Date()) -> ActivityMomentum {
        let calendar = utcCalendar()
        let today = calendar.startOfDay(for: today)
        let grouped = Dictionary(grouping: daily.compactMap { row in
            parseStatsDay(row.day).map { (calendar.startOfDay(for: $0), row) }
        }, by: \.0)
        let activeDates = Set(grouped.compactMap { date, values in
            values.contains {
                $0.1.sessions > 0 || $0.1.apiCalls > 0
            } ? date : nil
        })
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        var cursor: Date? = activeDates.contains(today)
            ? today
            : (activeDates.contains(yesterday) ? yesterday : nil)
        var current = 0
        while let day = cursor, activeDates.contains(day) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }

        var longest = 0
        var running = 0
        var previous: Date?
        for date in activeDates.sorted() {
            if let previous,
               calendar.date(byAdding: .day, value: 1, to: previous) == date {
                running += 1
            } else {
                running = 1
            }
            longest = max(longest, running)
            previous = date
        }

        let weekStart = calendar.date(
            byAdding: .day,
            value: -6,
            to: today
        )!
        let weeklyRows = grouped.flatMap { date, values in
            date >= weekStart && date <= today
                ? values.map(\.1)
                : []
        }
        let best = grouped.values.map { rows in
            rows.reduce(Int64(0)) {
                saturatingUsageAdd($0, $1.1.sessions)
            }
        }.max() ?? 0
        return ActivityMomentum(
            currentStreak: current,
            longestStreak: longest,
            activeDays: activeDates.count,
            weeklySessions: weeklyRows.reduce(0) {
                saturatingUsageAdd($0, $1.sessions)
            },
            weeklyCalls: weeklyRows.reduce(0) {
                saturatingUsageAdd($0, $1.apiCalls)
            },
            bestDaySessions: best
        )
    }
}

struct HeatmapProjection {
    let today: Date
    let start: Date
    let values: [Int64]
    let maximum: Int64

    init(daily: [DailyGatewayStats], now: Date = Date()) {
        let calendar = utcCalendar()
        today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilSaturday = (7 - weekday + 7) % 7
        let end = calendar.date(
            byAdding: .day,
            value: daysUntilSaturday,
            to: today
        )!
        let startDate = calendar.date(
            byAdding: .day,
            value: -90,
            to: end
        )!
        start = startDate
        var activity: [Date: Int64] = [:]
        for row in daily {
            guard let parsed = parseStatsDay(row.day) else {
                continue
            }
            let date = calendar.startOfDay(for: parsed)
            let value: Int64 = if row.apiCalls > 0 {
                row.apiCalls
            } else if row.sessions > 0 {
                row.sessions
            } else if row.recordedTokens > 0 {
                1
            } else {
                0
            }
            activity[date] = saturatingUsageAdd(
                activity[date, default: 0],
                value
            )
        }
        let projectedValues = (0..<91).map { offset in
            let date = calendar.date(
                byAdding: .day,
                value: offset,
                to: startDate
            )!
            return activity[date, default: 0]
        }
        values = projectedValues
        maximum = projectedValues.max() ?? 0
    }

    func date(at offset: Int) -> Date {
        utcCalendar().date(
            byAdding: .day,
            value: offset,
            to: start
        )!
    }

    func level(at offset: Int) -> Int {
        let value = values[offset]
        guard value > 0, maximum > 0 else {
            return 0
        }
        let scaled = log(Double(value) + 1) / log(Double(maximum) + 1)
        return min(4, max(1, Int(ceil(scaled * 4))))
    }

    var accessibilityLabel: String {
        let count = values.filter { $0 > 0 }.count
        return "Activity over the last 13 weeks. \(count) "
            + (count == 1 ? "active day. " : "active days. ")
            + "Darker squares mean more recorded model calls."
    }
}

func parseStatsDay(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = utcCalendar()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
}

func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}
