import Foundation

@main
struct LUTDisplayNameCheck {
    static func main() {
        let cases: [(raw: String, brand: String?, expected: String)] = [
            ("Warm_18.A049_12291747_S", nil, "Warm 18"),
            ("WOODEN_GOLD__20.C0021", nil, "WOODEN GOLD 20"),
            ("00_Gara_CineLut03", nil, "Gara CineLut03"),
            ("1_25.A002_02161553_C053", "FreshLUTs", "FreshLUTs Look 1"),
            ("1_SGamut3CineSLog3_To_LC-709", nil, "SGamut3CineSLog3 To LC-709"),
            ("65MM_FILM_01", nil, "65MM FILM 01"),
            ("12 Years a Slave", nil, "12 Years a Slave"),
            ("Look.v2024", nil, "Look.v2024"),
            ("Look.V2024", nil, "Look.V2024"),
            ("1.1", "FreshLUTs", "FreshLUTs Look 1.1"),
            ("1.2", "FreshLUTs", "FreshLUTs Look 1.2"),
        ]

        for item in cases {
            let actual = LUTDisplayName.normalized(item.raw, brand: item.brand)
            guard actual == item.expected else {
                fputs("FAIL: \(item.raw) -> \(actual), expected \(item.expected)\n", stderr)
                exit(1)
            }
        }
        print("LUT display-name checks passed (\(cases.count) cases)")
    }
}
