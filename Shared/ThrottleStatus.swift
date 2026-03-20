import Foundation

struct ThrottleStatus: Sendable {
    let is2x: Bool
    let isPeakHour: Bool
    let isPromoActive: Bool
    let countdownSeconds: Int
    let countdownLabel: String

    var statusText: String {
        if !isPromoActive {
            return "Standard"
        }
        return is2x ? "2X Active" : "Peak Hours"
    }

    var countdownFormatted: String {
        let total = max(countdownSeconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        }
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        }
        return String(format: "%dm %ds", minutes, seconds)
    }
}

struct ThrottleCalculator: Sendable {
    // Promo period: March 13, 2026 00:00 UTC to March 28, 2026 00:00 UTC
    private let promoStart: Date
    private let promoEnd: Date
    private let easternTimeZone: TimeZone

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        var startComponents = DateComponents()
        startComponents.year = 2026
        startComponents.month = 3
        startComponents.day = 13
        startComponents.hour = 0
        startComponents.minute = 0
        startComponents.second = 0
        promoStart = calendar.date(from: startComponents)!

        var endComponents = DateComponents()
        endComponents.year = 2026
        endComponents.month = 3
        endComponents.day = 28
        endComponents.hour = 0
        endComponents.minute = 0
        endComponents.second = 0
        promoEnd = calendar.date(from: endComponents)!

        easternTimeZone = TimeZone(identifier: "America/New_York")!
    }

    func nextTransitionDate(after date: Date = Date()) -> Date {
        let status = calculate(at: date)
        return date.addingTimeInterval(Double(max(status.countdownSeconds, 60)))
    }

    func calculate(at date: Date = Date()) -> ThrottleStatus {
        let isPromoActive = date >= promoStart && date < promoEnd

        if !isPromoActive {
            let isBeforePromo = date < promoStart
            return ThrottleStatus(
                is2x: false,
                isPeakHour: false,
                isPromoActive: false,
                countdownSeconds: isBeforePromo ? Int(promoStart.timeIntervalSince(date)) : 0,
                countdownLabel: isBeforePromo ? "2X starts in" : "Promotion ended"
            )
        }

        var etCalendar = Calendar(identifier: .gregorian)
        etCalendar.timeZone = easternTimeZone

        let weekday = etCalendar.component(.weekday, from: date)
        let hour = etCalendar.component(.hour, from: date)

        let isWeekday = weekday >= 2 && weekday <= 6
        let isPeakHour = isWeekday && hour >= 8 && hour < 14
        let is2x = !isPeakHour

        let countdownSeconds: Int
        let countdownLabel: String

        if isPeakHour {
            var next = etCalendar.dateComponents([.year, .month, .day], from: date)
            next.hour = 14; next.minute = 0; next.second = 0
            countdownSeconds = Int(etCalendar.date(from: next)!.timeIntervalSince(date))
            countdownLabel = "2X resumes in"
        } else if isWeekday && hour < 8 {
            var next = etCalendar.dateComponents([.year, .month, .day], from: date)
            next.hour = 8; next.minute = 0; next.second = 0
            countdownSeconds = Int(etCalendar.date(from: next)!.timeIntervalSince(date))
            countdownLabel = "2X ends in"
        } else {
            var searchDate = date
            for _ in 0..<8 {
                searchDate = etCalendar.date(byAdding: .day, value: 1, to: searchDate)!
                let wd = etCalendar.component(.weekday, from: searchDate)
                if wd >= 2 && wd <= 6 {
                    var next = etCalendar.dateComponents([.year, .month, .day], from: searchDate)
                    next.hour = 8; next.minute = 0; next.second = 0
                    let nextChange = etCalendar.date(from: next)!

                    if nextChange > promoEnd {
                        return ThrottleStatus(
                            is2x: true, isPeakHour: false, isPromoActive: true,
                            countdownSeconds: max(Int(promoEnd.timeIntervalSince(date)), 0),
                            countdownLabel: "Promo ends in"
                        )
                    }

                    return ThrottleStatus(
                        is2x: true, isPeakHour: false, isPromoActive: true,
                        countdownSeconds: Int(nextChange.timeIntervalSince(date)),
                        countdownLabel: "2X ends in"
                    )
                }
            }
            countdownSeconds = 0
            countdownLabel = "2X ends in"
        }

        return ThrottleStatus(
            is2x: is2x, isPeakHour: isPeakHour, isPromoActive: true,
            countdownSeconds: max(countdownSeconds, 0),
            countdownLabel: countdownLabel
        )
    }
}
