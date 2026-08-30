import Foundation

func formatCompact(_ value: Int64) -> String {
    if value >= 1_000_000_000 {
        return String(format: "%.1fB", Double(value) / 1_000_000_000)
    }
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
        return String(format: "%.1fk", Double(value) / 1_000)
    }
    return String(value)
}

func formatWhole(_ value: Int64) -> String {
    value.formatted(.number.grouping(.automatic))
}

func formatStatsDate(_ value: String) -> String {
    guard let date = parseStatsDay(value) else {
        return value
    }
    return formatMonthDay(date)
}

func formatHeatmapDate(_ date: Date) -> String {
    formatMonthDay(date)
}

private func formatMonthDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = utcCalendar()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}
