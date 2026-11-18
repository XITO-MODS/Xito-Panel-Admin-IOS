import SwiftUI

struct ContentView: View {
    @StateObject private var service = FirebaseService()

    @State private var apiKey = ""
    @State private var adminEmail = ""
    @State private var adminPassword = ""

    @State private var selectedPresetIndex = 0
    @State private var customDays = ""
    @State private var singleDevice = true
    @State private var keyCode = ""
    @State private var keyNote = ""

    let presets: [(title: String, hours: Int, tag: String, perm: Bool)] = [
        ("1 Día (24h)", 24, "1D", false),
        ("3 Días", 72, "3D", false),
        ("7 Días", 168, "7D", false),
        ("30 Días", 720, "30D", false),
        ("Permanente", 876000, "VIP", true)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.02, green: 0.08, blue: 0.05).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Estado
                        VStack(alignment: .leading, spacing: 6) {
                            Text("XITO MODS • KEY ADMIN")
                                .font(.title2).bold()
                                .foregroundColor(Color(red: 0, green: 0.9, blue: 0.46))
                            Text(service.statusMessage)
                                .font(.caption)
                                .foregroundColor(.green.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(red: 0.05, green: 0.15, blue: 0.09))
                        .cornerRadius(14)

                        // Auth Admin opcional
                        VStack(alignment: .leading, spacing: 8) {
                            Text(service.isAuthenticated ? "Sesión Admin Activa" : "Login Admin (Opcional en modo prueba)")
                                .font(.caption).bold()
                                .foregroundColor(Color(red: 0, green: 0.9, blue: 0.46))
                            TextField("Clave de API web (AIzaSy...)", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                            TextField("Correo Admin", text: $adminEmail)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                            SecureField("Contraseña Admin", text: $adminPassword)
                                .textFieldStyle(.roundedBorder)
                            Button("Iniciar Sesión Admin") {
                                service.signInAdmin(apiKey: apiKey, email: adminEmail, password: adminPassword)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding()
                        .background(Color(red: 0.05, green: 0.15, blue: 0.09))
                        .cornerRadius(14)

                        // Crear Key
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CREAR NUEVA KEY")
                                .font(.headline)
                                .foregroundColor(Color(red: 0, green: 0.9, blue: 0.46))

                            Picker("Duración", selection: $selectedPresetIndex) {
                                ForEach(0..<presets.count, id: \.self) { idx in
                                    Text(presets[idx].title).tag(idx)
                                }
                            }
                            .pickerStyle(.menu)

                            TextField("Días personalizados (opcional)", text: $customDays)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)

                            Toggle("1 Solo Dispositivo (Bloqueo HWID)", isOn: $singleDevice)
                                .tint(.green)

                            TextField("Código (vacío = aleatorio)", text: $keyCode)
                                .textFieldStyle(.roundedBorder)

                            TextField("Nota / Cliente (opcional)", text: $keyNote)
                                .textFieldStyle(.roundedBorder)

                            Button(action: createKey) {
                                Text("GENERAR Y SUBIR KEY")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(red: 0, green: 0.78, blue: 0.33))
                                    .foregroundColor(.black)
                                    .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color(red: 0.05, green: 0.15, blue: 0.09))
                        .cornerRadius(14)

                        // Lista de Keys
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("KEYS EN SERVIDOR")
                                    .font(.headline)
                                    .foregroundColor(Color(red: 0, green: 0.9, blue: 0.46))
                                Spacer()
                                Button("Actualizar") {
                                    service.fetchKeys()
                                }
                                .font(.caption).bold()
                                .foregroundColor(.green)
                            }

                            ForEach(service.keys) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.key)
                                        .font(.system(.body, design: .monospaced)).bold()
                                        .foregroundColor(.white)
                                    Text(item.permanent ? "Permanente" : "\(item.durationHours)h • \(item.maxDevices == 1 ? "1 Disp." : "Multi")")
                                        .font(.caption)
                                        .foregroundColor(.green.opacity(0.8))
                                    HStack {
                                        Button("Copiar") {
                                            UIPasteboard.general.string = item.key
                                            service.statusMessage = "Copiada: \(item.key)"
                                        }
                                        .buttonStyle(.bordered)
                                        Button("Reset HWID") {
                                            var updated = item
                                            updated.boundDevice = ""
                                            service.saveKey(updated)
                                        }
                                        .buttonStyle(.bordered)
                                        Button("Borrar", role: .destructive) {
                                            service.deleteKey(item.key)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(red: 0.07, green: 0.22, blue: 0.14))
                                .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color(red: 0.05, green: 0.15, blue: 0.09))
                        .cornerRadius(14)
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                service.fetchKeys()
            }
        }
    }

    func createKey() {
        let preset = presets[selectedPresetIndex]
        var hours = preset.hours
        var tag = preset.tag
        var isPerm = preset.perm

        if let days = Int(customDays.trimmingCharacters(in: .whitespaces)), days > 0 {
            hours = days * 24
            tag = "\(days)D"
            isPerm = false
        }

        let trimmedCode = keyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCode = trimmedCode.isEmpty ? FirebaseService.generateRandomCode(tag: tag) : trimmedCode

        let newItem = LicenseKeyItem(
            key: finalCode,
            active: true,
            permanent: isPerm,
            durationHours: hours,
            maxDevices: singleDevice ? 1 : 999,
            boundDevice: "",
            firstLoginAt: 0,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            note: keyNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        service.saveKey(newItem)
        UIPasteboard.general.string = finalCode
        keyCode = ""
    }
}
