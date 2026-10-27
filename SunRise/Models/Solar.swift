import Foundation
import simd

struct City: Identifiable {
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZone: String
    var id: String { name }
}

struct SunriseEvent: Identifiable {
    let city: City
    let date: Date
    var id: String { city.id }
}

enum Solar {
    static let cities: [City] = [
        .init(name: "东京", country: "日本", latitude: 35.68, longitude: 139.69, timeZone: "Asia/Tokyo"),
        .init(name: "北京", country: "中国", latitude: 39.90, longitude: 116.40, timeZone: "Asia/Shanghai"),
        .init(name: "上海", country: "中国", latitude: 31.23, longitude: 121.47, timeZone: "Asia/Shanghai"),
        .init(name: "香港", country: "中国", latitude: 22.32, longitude: 114.17, timeZone: "Asia/Hong_Kong"),
        .init(name: "台北", country: "中国台湾", latitude: 25.03, longitude: 121.57, timeZone: "Asia/Taipei"),
        .init(name: "首尔", country: "韩国", latitude: 37.57, longitude: 126.98, timeZone: "Asia/Seoul"),
        .init(name: "新加坡", country: "新加坡", latitude: 1.35, longitude: 103.82, timeZone: "Asia/Singapore"),
        .init(name: "曼谷", country: "泰国", latitude: 13.76, longitude: 100.50, timeZone: "Asia/Bangkok"),
        .init(name: "新德里", country: "印度", latitude: 28.61, longitude: 77.21, timeZone: "Asia/Kolkata"),
        .init(name: "迪拜", country: "阿联酋", latitude: 25.20, longitude: 55.27, timeZone: "Asia/Dubai"),
        .init(name: "伊斯坦布尔", country: "土耳其", latitude: 41.01, longitude: 28.98, timeZone: "Europe/Istanbul"),
        .init(name: "开罗", country: "埃及", latitude: 30.04, longitude: 31.24, timeZone: "Africa/Cairo"),
        .init(name: "内罗毕", country: "肯尼亚", latitude: -1.29, longitude: 36.82, timeZone: "Africa/Nairobi"),
        .init(name: "开普敦", country: "南非", latitude: -33.92, longitude: 18.42, timeZone: "Africa/Johannesburg"),
        .init(name: "伦敦", country: "英国", latitude: 51.51, longitude: -0.13, timeZone: "Europe/London"),
        .init(name: "巴黎", country: "法国", latitude: 48.86, longitude: 2.35, timeZone: "Europe/Paris"),
        .init(name: "罗马", country: "意大利", latitude: 41.90, longitude: 12.50, timeZone: "Europe/Rome"),
        .init(name: "雷克雅未克", country: "冰岛", latitude: 64.15, longitude: -21.94, timeZone: "Atlantic/Reykjavik"),
        .init(name: "纽约", country: "美国", latitude: 40.71, longitude: -74.01, timeZone: "America/New_York"),
        .init(name: "洛杉矶", country: "美国", latitude: 34.05, longitude: -118.24, timeZone: "America/Los_Angeles"),
        .init(name: "温哥华", country: "加拿大", latitude: 49.28, longitude: -123.12, timeZone: "America/Vancouver"),
        .init(name: "墨西哥城", country: "墨西哥", latitude: 19.43, longitude: -99.13, timeZone: "America/Mexico_City"),
        .init(name: "里约热内卢", country: "巴西", latitude: -22.91, longitude: -43.17, timeZone: "America/Sao_Paulo"),
        .init(name: "布宜诺斯艾利斯", country: "阿根廷", latitude: -34.60, longitude: -58.38, timeZone: "America/Argentina/Buenos_Aires"),
        .init(name: "檀香山", country: "美国", latitude: 21.31, longitude: -157.86, timeZone: "Pacific/Honolulu"),
        .init(name: "悉尼", country: "澳大利亚", latitude: -33.87, longitude: 151.21, timeZone: "Australia/Sydney"),
        .init(name: "奥克兰", country: "新西兰", latitude: -36.85, longitude: 174.76, timeZone: "Pacific/Auckland")
    ]

    // NOAA's approximate solar coordinates: declination and equation of time.
    static func coordinates(at date: Date) -> (declination: Double, longitude: Double) {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (jd - 2451545.0) / 36525
        let rad = Double.pi / 180
        let l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = (357.52911 + t * (35999.05029 - 0.0001537 * t)) * rad
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2*m) * (0.019993 - 0.000101*t) + sin(3*m) * 0.000289
        let omega = (125.04 - 1934.136 * t) * rad
        let lambda = (l0 + c - 0.00569 - 0.00478 * sin(omega)) * rad
        let epsilon = (23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60 + 0.00256 * cos(omega)) * rad
        let declination = asin(sin(epsilon) * sin(lambda))
        let y = pow(tan(epsilon / 2), 2)
        let l = l0 * rad
        let eq = 4 / rad * (y * sin(2*l) - 2*e*sin(m) + 4*e*y*sin(m)*cos(2*l) - 0.5*y*y*sin(4*l) - 1.25*e*e*sin(2*m))
        let seconds = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400)
        let utcMinutes = (seconds + 86400).truncatingRemainder(dividingBy: 86400) / 60
        let longitude = (720 - utcMinutes - eq) / 4 * rad
        return (declination, longitude)
    }

    static func direction(at date: Date) -> SIMD3<Double> {
        let p = coordinates(at: date)
        return SIMD3(cos(p.declination) * sin(p.longitude), sin(p.declination), cos(p.declination) * cos(p.longitude))
    }

    static func altitude(at date: Date, city: City) -> Double {
        let lat = city.latitude * .pi / 180, lon = city.longitude * .pi / 180
        let point = SIMD3(cos(lat)*sin(lon), sin(lat), cos(lat)*cos(lon))
        return asin(max(-1, min(1, simd_dot(point, direction(at: date))))) * 180 / .pi
    }

    // Find the rising crossing of -0.833°, including standard refraction and solar radius.
    static func nearestSunrise(to date: Date, city: City) -> Date? {
        let start = date.addingTimeInterval(-18 * 3600)
        let step: TimeInterval = 900
        var previous = start
        var previousAltitude = altitude(at: previous, city: city) + 0.833
        var events: [Date] = []
        for i in 1...144 {
            let current = start.addingTimeInterval(Double(i) * step)
            let value = altitude(at: current, city: city) + 0.833
            if previousAltitude < 0 && value >= 0 {
                var lo = previous, hi = current
                for _ in 0..<12 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                    if altitude(at: mid, city: city) + 0.833 < 0 { lo = mid } else { hi = mid }
                }
                events.append(hi)
            }
            previous = current
            previousAltitude = value
        }
        return events.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
    }

    static func closestEvents(to date: Date) -> [SunriseEvent] {
        cities.compactMap { city in nearestSunrise(to: date, city: city).map { SunriseEvent(city: city, date: $0) } }
            .sorted { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
