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
    
    let items = extractMusicResponsiveItems(from: json).prefix(1)
    for item in items {
        print(String(data: try! JSONSerialization.data(withJSONObject: item, options: .prettyPrinted), encoding: .utf8)!)
    }
}
await testDuration()
