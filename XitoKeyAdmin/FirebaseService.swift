import Foundation
import Combine

struct LicenseKeyItem: Identifiable, Codable {
    var id: String { key }
    let key: String
    var active: Bool
    var permanent: Bool
    var durationHours: Int
    var maxDevices: Int
    var boundDevice: String
    var firstLoginAt: Int64
    var createdAt: Int64
    var note: String?
}

class FirebaseService: ObservableObject {
    static let dbURL = "https://xito-mods-default-rtdb.firebaseio.com"
    static let authURL = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword"

    @Published var keys: [LicenseKeyItem] = []
    @Published var statusMessage: String = "Conectado a xito-mods"
    @Published var isAuthenticated: Bool = false
    @Published var idToken: String = UserDefaults.standard.string(forKey: "xito_id_token") ?? ""

    init() {
        isAuthenticated = !idToken.isEmpty
    }

    func signInAdmin(apiKey: String, email: String, password: String) {
        let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        guard let url = URL(string: "\(Self.authURL)?key=\(encodedKey)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["email": email, "password": password, "returnSecureToken": true]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                if let err = err {
                    self.statusMessage = "Error: \(err.localizedDescription)"
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = json["idToken"] as? String else {
                    self.statusMessage = "Credenciales inválidas en Firebase Auth"
                    return
                }
                self.idToken = token
                self.isAuthenticated = true
                UserDefaults.standard.set(token, forKey: "xito_id_token")
                self.statusMessage = "Sesión Admin iniciada"
                self.fetchKeys()
            }
        }.resume()
    }

    private func buildURL(path: String) -> URL? {
        var urlString = Self.dbURL + path
        if !idToken.isEmpty {
            urlString += "?auth=" + (idToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        }
        return URL(string: urlString)
    }

    func fetchKeys() {
        guard let url = buildURL(path: "/keys.json") else { return }
        URLSession.shared.dataTask(with: url) { data, _, err in
            DispatchQueue.main.async {
                if let err = err {
                    self.statusMessage = "Error de red: \(err.localizedDescription)"
                    return
                }
                guard let data = data,
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                    self.keys = []
                    return
                }
                var loaded: [LicenseKeyItem] = []
                for (_, val) in dict {
                    if let keyName = val["key"] as? String {
                        let item = LicenseKeyItem(
                            key: keyName,
                            active: (val["active"] as? Bool) ?? true,
                            permanent: (val["permanent"] as? Bool) ?? false,
                            durationHours: (val["durationHours"] as? Int) ?? 24,
                            maxDevices: (val["maxDevices"] as? Int) ?? 1,
                            boundDevice: (val["boundDevice"] as? String) ?? "",
                            firstLoginAt: (val["firstLoginAt"] as? Int64) ?? 0,
                            createdAt: (val["createdAt"] as? Int64) ?? 0,
                            note: val["note"] as? String
                        )
                        loaded.append(item)
                    }
                }
                self.keys = loaded.sorted { $0.createdAt > $1.createdAt }
                self.statusMessage = "Sincronizado (\(loaded.count) keys)"
            }
        }.resume()
    }

    func saveKey(_ item: LicenseKeyItem) {
        let encodedKey = item.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.key
        guard let url = buildURL(path: "/keys/\(encodedKey).json") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(item)

        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                self.statusMessage = "Key guardada: \(item.key)"
                self.fetchKeys()
            }
        }.resume()
    }

    func deleteKey(_ keyName: String) {
        let encodedKey = keyName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? keyName
        guard let url = buildURL(path: "/keys/\(encodedKey).json") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"

        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                self.statusMessage = "Eliminada: \(keyName)"
                self.fetchKeys()
            }
        }.resume()
    }

    static func generateRandomCode(tag: String) -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let suffix = String((0..<6).map { _ in chars.randomElement()! })
        return "XITO-\(tag)-\(suffix)"
    }
}
