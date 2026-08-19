import Foundation

func testDuration() async {
    let query = "Sơn Tùng M-TP Nơi này có anh"
    guard let url = URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false") else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

    let body: [String: Any] = [
        "context": [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": "1.20231214.00.00",
                "hl": "en"
            ]
        ],
        "query": query
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let (data, _) = try! await URLSession.shared.data(for: request)
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    
    func extractMusicResponsiveItems(from object: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 20 else { return [] }
        var results: [[String: Any]] = []

        if let dict = object as? [String: Any] {
            if let renderer = dict["musicResponsiveListItemRenderer"] as? [String: Any] {
                results.append(renderer)
            }
            for value in dict.values {
                results.append(contentsOf: extractMusicResponsiveItems(from: value, depth: depth + 1))
            }
        } else if let array = object as? [Any] {
            for item in array {
                results.append(contentsOf: extractMusicResponsiveItems(from: item, depth: depth + 1))
            }
        }
        return results
    }
    
    let items = extractMusicResponsiveItems(from: json).prefix(3)
    for item in items {
        var allRunsText: [String] = []
        if let flexColumns = item["flexColumns"] as? [[String: Any]] {
            for col in flexColumns {
                if let renderer = col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                   let textObj = renderer["text"] as? [String: Any],
                   let runs = textObj["runs"] as? [[String: Any]] {
                    let texts = runs.compactMap { $0["text"] as? String }
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { $0 != "•" && !$0.isEmpty }
                    allRunsText.append(contentsOf: texts)
                }
            }
        }
        
        if let fixedColumns = item["fixedColumns"] as? [[String: Any]] {
            for col in fixedColumns {
                if let renderer = col["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
                   let textObj = renderer["text"] as? [String: Any],
                   let runs = textObj["runs"] as? [[String: Any]] {
                    let texts = runs.compactMap { $0["text"] as? String }
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { $0 != "•" && !$0.isEmpty }
                    allRunsText.append(contentsOf: texts)
                }
            }
        }
        print("Runs:", allRunsText)
    }
}
await testDuration()
