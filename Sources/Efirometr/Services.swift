import Foundation
import Darwin

/// Reads 64-bit byte counters of a network interface via sysctl(NET_RT_IFLIST2).
enum InterfaceCounters {
    static func bytes(for name: String) -> (rx: UInt64, tx: UInt64)? {
        let index = if_nametoindex(name)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return nil }
        return buf.withUnsafeBytes { raw -> (UInt64, UInt64)? in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                if Int32(hdr.ifm_type) == RTM_IFINFO2 && UInt32(hdr.ifm_index) == index {
                    let h2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    return (h2.ifm_data.ifi_ibytes, h2.ifm_data.ifi_obytes)
                }
                guard hdr.ifm_msglen > 0 else { break }
                offset += Int(hdr.ifm_msglen)
            }
            return nil
        }
    }
}

enum Format {
    static func speed(_ bytesPerSecond: Double, compact: Bool = false) -> String {
        let bits = bytesPerSecond * 8
        if compact && bits < 1000 { return bits < 50 ? "0К" : "0.\(Int(bits / 100))К" }
        let units = compact ? ["б", "К", "М", "Г"] : ["бит/с", "Кбит/с", "Мбит/с", "Гбит/с"]
        var v = bits
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        let digits = v < 10 && i > 0 ? 1 : 0
        return String(format: "%.\(digits)f%@%@", v, compact ? "" : " ", units[i])
    }
}

/// Runs the system `ping` and parses its summary.
enum Pinger {
    static func run(label: String, host: String, count: Int = 20) async -> LatencyResult? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/sbin/ping")
                p.arguments = ["-c", "\(count)", "-i", "0.2", "-t", "15", host]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do { try p.run() } catch { cont.resume(returning: nil); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let out = String(decoding: data, as: UTF8.self)
                cont.resume(returning: parse(out, label: label, host: host))
            }
        }
    }

    /// Uses the median rather than the mean: Wi‑Fi power saving makes occasional pings spike to 100+ ms.
    static func parse(_ out: String, label: String, host: String) -> LatencyResult? {
        let times: [Double] = out.split(separator: "\n").compactMap { line in
            guard let r = line.range(of: "time=") else { return nil }
            return Double(line[r.upperBound...].prefix { "0123456789.".contains($0) })
        }
        var sent = 0
        if let r = out.range(of: #"(\d+) packets transmitted"#, options: .regularExpression) {
            sent = Int(out[r].split(separator: " ").first ?? "") ?? 0
        }
        guard sent > 0 else { return nil }
        let loss = 1 - Double(times.count) / Double(sent)
        guard !times.isEmpty else { return LatencyResult(label: label, host: host, avg: 0, min: 0, max: 0, jitter: 0, loss: 1) }
        let sorted = times.sorted()
        let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let jitter = times.count > 1 ? zip(times, times.dropFirst()).map { abs($0 - $1) }.reduce(0, +) / Double(times.count - 1) : 0
        return LatencyResult(label: label, host: host, avg: median, min: sorted.first!, max: sorted.last!, jitter: jitter, loss: max(0, loss))
    }
}

enum SystemInfo {
    static func run(_ path: String, _ args: [String]) -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return Data() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    static func defaultGateway() -> String? {
        let out = String(decoding: run("/sbin/route", ["-n", "get", "default"]), as: UTF8.self)
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 && parts[0] == "gateway" { return parts[1] }
        }
        return nil
    }

    /// Hardware details CoreWLAN doesn't expose (card type, firmware, PHY modes).
    static func load(into caps: inout Capabilities) {
        caps.gateway = defaultGateway()
        let wifi = run("/usr/sbin/system_profiler", ["SPAirPortDataType", "SPHardwareDataType", "-json"])
        guard let json = try? JSONSerialization.jsonObject(with: wifi) as? [String: Any] else { return }
        if let hw = (json["SPHardwareDataType"] as? [[String: Any]])?.first {
            caps.macName = hw["machine_name"] as? String ?? caps.macName
            caps.macModel = hw["machine_model"] as? String ?? ""
            caps.chip = hw["chip_type"] as? String ?? hw["cpu_type"] as? String ?? ""
        }
        if let ap = (json["SPAirPortDataType"] as? [[String: Any]])?.first,
           let ifaces = ap["spairport_airport_interfaces"] as? [[String: Any]],
           let en = ifaces.first(where: { $0["spairport_wireless_card_type"] != nil }) {
            let card = en["spairport_wireless_card_type"] as? String ?? ""
            caps.cardType = card.range(of: #"\(.*\)"#, options: .regularExpression).map { String(card[$0]) } ?? card
            caps.firmware = (en["spairport_wireless_firmware_version"] as? String)?.components(separatedBy: "\n").first ?? ""
            caps.phyModes = en["spairport_supported_phymodes"] as? String ?? ""
            if caps.countryCode.isEmpty { caps.countryCode = en["spairport_wireless_country_code"] as? String ?? "" }
        }
    }
}
