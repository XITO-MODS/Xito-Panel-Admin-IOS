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
    static let refreshURL = "https://securetoken.googleapis.com/v1/token"

    @Published var keys: [LicenseKeyItem] = []
    @Published var statusMessage: String = "Listo para conectar a xito-mods"
    @Published var isErrorStatus: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var adminUid: String = UserDefaults.standard.string(forKey: "xito_admin_uid") ?? ""
    @Published var idToken: String = UserDefaults.standard.string(forKey: "xito_id_token") ?? ""
    @Published var refreshToken: String = UserDefaults.standard.string(forKey: "xito_refresh_token") ?? ""
    @Published var savedApiKey: String = UserDefaults.standard.string(forKey: "xito_api_key") ?? ""
    @Published var savedEmail: String = UserDefaults.standard.string(forKey: "xito_admin_email") ?? ""

    init() {
        isAuthenticated = !idToken.isEmpty
    }

    func signInAdmin(apiKey: String, email: String, password: String) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPass = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanKey.isEmpty, !cleanEmail.isEmpty, !cleanPass.isEmpty else {
            self.setStatus("Completa Clave de API web, correo y contraseña.", isError: true)
            return
        }

        let encodedKey = cleanKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanKey
        guard let url = URL(string: "\(Self.authURL)?key=\(encodedKey)") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["email": cleanEmail, "password": cleanPass, "returnSecureToken": true]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        self.setStatus("Iniciando sesión en Firebase Auth...", isError: false)

        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                if let err = err {
                    self.setStatus("Error de red: \(err.localizedDescription)", isError: true)
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.setStatus("Respuesta inválida de Firebase Auth", isError: true)
                    return
                }
                if let errorObj = json["error"] as? [String: Any],
                   let msg = errorObj["message"] as? String {
                    self.setStatus("Auth Error: \(msg)", isError: true)
                    return
                }
                guard let token = json["idToken"] as? String else {
                    self.setStatus("No se recibió token de Firebase Auth", isError: true)
                    return
                }

                self.idToken = token
                self.refreshToken = (json["refreshToken"] as? String) ?? ""
                self.adminUid = (json["localId"] as? String) ?? ""
                self.savedApiKey = cleanKey
                self.savedEmail = cleanEmail
                self.isAuthenticated = true

                UserDefaults.standard.set(token, forKey: "xito_id_token")
                UserDefaults.standard.set(self.refreshToken, forKey: "xito_refresh_token")
                UserDefaults.standard.set(self.adminUid, forKey: "xito_admin_uid")
                UserDefaults.standard.set(cleanKey, forKey: "xito_api_key")
                UserDefaults.standard.set(cleanEmail, forKey: "xito_admin_email")

                self.setStatus("Sesión Admin activa (UID: \(self.adminUid))", isError: false)
                self.fetchKeys()
            }
        }.resume()
    }

    func signOut() {
        idToken = ""
        refreshToken = ""
        adminUid = ""
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "xito_id_token")
        UserDefaults.standard.removeObject(forKey: "xito_refresh_token")
        UserDefaults.standard.removeObject(forKey: "xito_admin_uid")
        setStatus("Sesión Admin cerrada", isError: false)
        fetchKeys()
    }

    private func refreshIdTokenIfPossible(completion: @escaping (Bool) -> Void) {
        guard !refreshToken.isEmpty, !savedApiKey.isEmpty else {
            completion(false)
            return
        }
        let encodedKey = savedApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? savedApiKey
        guard let url = URL(string: "\(Self.refreshURL)?key=\(encodedKey)") else {
            completion(false)
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyStr = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        req.httpBody = bodyStr.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let newToken = json["id_token"] as? String else {
                    completion(false)
                    return
                }
                self.idToken = newToken
                if let newRefresh = json["refresh_token"] as? String {
                    self.refreshToken = newRefresh
                    UserDefaults.standard.set(newRefresh, forKey: "xito_refresh_token")
                }
                UserDefaults.standard.set(newToken, forKey: "xito_id_token")
                completion(true)
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

    private func setStatus(_ msg: String, isError: Bool) {
        self.statusMessage = msg
        self.isErrorStatus = isError
    }

    func fetchKeys(didRetryRefresh: Bool = false) {
        guard let url = buildURL(path: "/keys.json") else { return }
        URLSession.shared.dataTask(with: url) { data, response, err in
            DispatchQueue.main.async {
                if let err = err {
                    self.setStatus("Error de red: \(err.localizedDescription)", isError: true)
                    return
                }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode == 401 && !didRetryRefresh {
                    self.refreshIdTokenIfPossible { refreshed in
                        if refreshed {
                            self.fetchKeys(didRetryRefresh: true)
                        } else {
                            self.setStatus("Sesión expirada (401). Vuelve a iniciar sesión Admin.", isError: true)
                        }
                    }
                    return
                }

                guard let data = data else {
                    self.setStatus("Sin respuesta de Firebase (HTTP \(statusCode))", isError: true)
                    return
                }

                let rawStr = String(data: data, encoding: .utf8) ?? ""
                if rawStr.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
                    self.keys = []
                    self.setStatus("Conectado: 0 keys en /keys", isError: false)
                    return
                }

                guard let rawObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.setStatus("Error leyendo JSON (HTTP \(statusCode))", isError: true)
                    return
                }

                if let fbError = rawObj["error"] as? String {
                    self.setStatus("Firebase denegó lectura: \(fbError). Revisa Reglas o inicia sesión.", isError: true)
                    return
                }

                var loaded: [LicenseKeyItem] = []
                for (dictKey, anyVal) in rawObj {
                    guard let val = anyVal as? [String: Any] else { continue }
                    let keyName = (val["key"] as? String) ?? dictKey
                    let durHours = (val["durationHours"] as? Int) ?? (val["durationHours"] as? NSNumber)?.intValue ?? 24
                    let maxDev = (val["maxDevices"] as? Int) ?? (val["maxDevices"] as? NSNumber)?.intValue ?? 1
                    let firstLogin = (val["firstLoginAt"] as? Int64) ?? (val["firstLoginAt"] as? NSNumber)?.int64Value ?? 0
                    let created = (val["createdAt"] as? Int64) ?? (val["createdAt"] as? NSNumber)?.int64Value ?? 0

                    let item = LicenseKeyItem(
                        key: keyName,
                        active: (val["active"] as? Bool) ?? true,
                        permanent: (val["permanent"] as? Bool) ?? false,
                        durationHours: durHours,
                        maxDevices: maxDev,
                        boundDevice: (val["boundDevice"] as? String) ?? "",
                        firstLoginAt: firstLogin,
                        createdAt: created,
                        note: val["note"] as? String
                    )
                    loaded.append(item)
                }

                self.keys = loaded.sorted { $0.createdAt > $1.createdAt }
                self.setStatus("Sincronizado: \(loaded.count) key(s) cargadas", isError: false)
            }
        }.resume()
    }

    func saveKey(_ item: LicenseKeyItem, didRetryRefresh: Bool = false) {
        let encodedKey = item.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.key
        guard let url = buildURL(path: "/keys/\(encodedKey).json") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(item)

        URLSession.shared.dataTask(with: req) { data, response, err in
            DispatchQueue.main.async {
                if let err = err {
                    self.setStatus("Error guardando: \(err.localizedDescription)", isError: true)
                    return
                }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode == 401 && !didRetryRefresh {
                    self.refreshIdTokenIfPossible { refreshed in
                        if refreshed {
                            self.saveKey(item, didRetryRefresh: true)
                        } else {
                            self.setStatus("Sesión expirada (401). Vuelve a iniciar sesión Admin.", isError: true)
                        }
                    }
                    return
                }

                if statusCode < 200 || statusCode >= 300 {
                    let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    self.setStatus("Firebase rechazó guardar (HTTP \(statusCode)): \(bodyText)", isError: true)
                    return
                }

                self.setStatus("Guardada en servidor: \(item.key)", isError: false)
                self.fetchKeys()
            }
        }.resume()
    }

    func deleteKey(_ keyName: String, didRetryRefresh: Bool = false) {
        let encodedKey = keyName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? keyName
        guard let url = buildURL(path: "/keys/\(encodedKey).json") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"

        URLSession.shared.dataTask(with: req) { data, response, err in
            DispatchQueue.main.async {
                if let err = err {
                    self.setStatus("Error eliminando: \(err.localizedDescription)", isError: true)
                    return
                }
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode == 401 && !didRetryRefresh {
                    self.refreshIdTokenIfPossible { refreshed in
                        if refreshed {
                            self.deleteKey(keyName, didRetryRefresh: true)
                        } else {
                            self.setStatus("Sesión expirada (401). Vuelve a iniciar sesión Admin.", isError: true)
                        }
                    }
                    return
                }
                if statusCode < 200 || statusCode >= 300 {
                    let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    self.setStatus("Firebase rechazó borrar (HTTP \(statusCode)): \(bodyText)", isError: true)
                    return
                }
                self.setStatus("Eliminada del servidor: \(keyName)", isError: false)
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
