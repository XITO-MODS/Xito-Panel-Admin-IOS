import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var service = FirebaseService()

    @State private var apiKey = UserDefaults.standard.string(forKey: "xito_api_key") ?? ""
    @State private var adminEmail = UserDefaults.standard.string(forKey: "xito_admin_email") ?? ""
    @State private var adminPassword = ""

    @State private var selectedPresetIndex = 0
    @State private var customDays = ""
    @State private var singleDevice = true
    @State private var keyCode = ""
    @State private var keyNote = ""

    @State private var searchText = ""
    @State private var editingKeyItem: LicenseKeyItem? = nil

    let presets: [(title: String, hours: Int, tag: String, perm: Bool)] = [
        ("1 Día (24h)", 24, "1D", false),
        ("3 Días", 72, "3D", false),
        ("7 Días", 168, "7D", false),
        ("30 Días", 720, "30D", false),
        ("Permanente", 876000, "VIP", true)
    ]

    var filteredKeys: [LicenseKeyItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return service.keys }
        return service.keys.filter {
            $0.key.lowercased().contains(q) || ($0.note ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.02, green: 0.08, blue: 0.05).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Estado del servidor
                        VStack(alignment: .leading, spacing: 6) {
                            Text("XITO MODS • KEY ADMIN")
                                .font(.title2).bold()
                                .foregroundColor(Color(red: 0, green: 0.9, blue: 0.46))
                            Text(service.statusMessage)
                                .font(.caption)
                                .foregroundColor(service.isErrorStatus ? .red : .green.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(red: 0.05, green: 0.15, blue: 0.09))
                        .cornerRadius(14)

                        // Auth Admin
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(service.isAuthenticated ? "Sesión Admin Activa" : "Login Admin (Firebase Auth)")
                                    .font(.caption).bold()
                                    .foregroundColor(Color(red: 0, green: 0.9, blue: 0.46))
                                Spacer()
                                if service.isAuthenticated {
                                    Button("Cerrar") {
                                        service.signOut()
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.red)
                                }
                            }
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

                        // Crear nueva key
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

                        // Lista de Keys en servidor
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("KEYS EN SERVIDOR (\(service.keys.count))")
                                    .font(.headline)
                                    .foregroundColor(Color(red: 0, green: 0.9, blue: 0.46))
                                Spacer()
                                Button("Actualizar") {
                                    service.fetchKeys()
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.green)
                            }

                            TextField("Buscar key o nota...", text: $searchText)
                                .textFieldStyle(.roundedBorder)

                            if filteredKeys.isEmpty {
                                Text("No hay keys para mostrar. Toca Actualizar o revisa la sesión/reglas.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(filteredKeys) { item in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(item.key)
                                                .font(.system(.body, design: .monospaced)).bold()
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text(statusBadge(for: item))
                                                .font(.system(size: 11, weight: .bold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(item.active ? Color.green.opacity(0.25) : Color.red.opacity(0.25))
                                                .foregroundColor(item.active ? .green : .red)
                                                .cornerRadius(6)
                                        }

                                        Text(metaDescription(for: item))
                                            .font(.caption)
                                            .foregroundColor(.green.opacity(0.85))

                                        if let note = item.note, !note.isEmpty {
                                            Text("Nota: \(note)")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }

                                        HStack(spacing: 6) {
                                            Button("Copiar") {
                                                UIPasteboard.general.string = item.key
                                                service.statusMessage = "Copiada: \(item.key)"
                                                service.isErrorStatus = false
                                            }
                                            .buttonStyle(.bordered)

                                            Button("Editar") {
                                                editingKeyItem = item
                                            }
                                            .buttonStyle(.bordered)

                                            Button("Reset") {
                                                var updated = item
                                                updated.boundDevice = ""
                                                updated.firstLoginAt = 0
                                                service.saveKey(updated)
                                            }
                                            .buttonStyle(.bordered)

                                            Button("Borrar", role: .destructive) {
                                                service.deleteKey(item.key)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                        .font(.system(size: 11, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(Color(red: 0.07, green: 0.22, blue: 0.14))
                                    .cornerRadius(10)
                                }
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
            .sheet(item: $editingKeyItem) { itemToEdit in
                EditKeySheet(item: itemToEdit) { updatedItem in
                    service.saveKey(updatedItem)
                }
            }
        }
    }

    func statusBadge(for item: LicenseKeyItem) -> String {
        if !item.active { return "Pausada" }
        if item.permanent { return "Permanente" }
        if item.firstLoginAt <= 0 { return "Sin usar (\(item.durationHours)h)" }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let totalMs = Int64(item.durationHours) * 3600 * 1000
        let remMs = totalMs - (nowMs - item.firstLoginAt)
        if remMs <= 0 { return "Vencida" }
        let hours = remMs / (3600 * 1000)
        return "\(hours)h rest."
    }

    func metaDescription(for item: LicenseKeyItem) -> String {
        let dur = item.permanent ? "Ilimitada" : "\(item.durationHours)h"
        let dev: String
        if item.maxDevices == 1 {
            dev = item.boundDevice.isEmpty ? "1 Disp. (Libre)" : "1 Disp. (\(item.boundDevice))"
        } else {
            dev = "Multidispositivo"
        }
        return "\(dur) • \(dev)"
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
        customDays = ""
        keyNote = ""
    }
}

struct EditKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    let originalItem: LicenseKeyItem
    let onSave: (LicenseKeyItem) -> Void

    @State private var isActive: Bool
    @State private var isPermanent: Bool
    @State private var durationHoursText: String
    @State private var isSingleDevice: Bool
    @State private var boundDeviceText: String
    @State private var resetTimer: Bool = false
    @State private var noteText: String

    init(item: LicenseKeyItem, onSave: @escaping (LicenseKeyItem) -> Void) {
        self.originalItem = item
        self.onSave = onSave
        _isActive = State(initialValue: item.active)
        _isPermanent = State(initialValue: item.permanent)
        _durationHoursText = State(initialValue: String(item.durationHours))
        _isSingleDevice = State(initialValue: item.maxDevices == 1)
        _boundDeviceText = State(initialValue: item.boundDevice)
        _noteText = State(initialValue: item.note ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Key")) {
                    Text(originalItem.key)
                        .font(.system(.body, design: .monospaced)).bold()
                }

                Section(header: Text("Estado y Duración")) {
                    Toggle("Key Activa", isOn: $isActive)
                    Toggle("Permanente (Sin vencimiento)", isOn: $isPermanent)
                    if !isPermanent {
                        TextField("Duración en horas (ej. 24, 168, 720)", text: $durationHoursText)
                            .keyboardType(.numberPad)
                    }
                    Toggle("Reiniciar tiempo de inicio", isOn: $resetTimer)
                }

                Section(header: Text("Dispositivo (HWID)")) {
                    Toggle("1 Solo Dispositivo", isOn: $isSingleDevice)
                    TextField("ID Dispositivo vinculado (vacío = libre)", text: $boundDeviceText)
                    Button("Limpiar HWID vinculado") {
                        boundDeviceText = ""
                    }
                }

                Section(header: Text("Nota")) {
                    TextField("Nota / Cliente", text: $noteText)
                }
            }
            .navigationTitle("Editar Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        var updated = originalItem
                        updated.active = isActive
                        updated.permanent = isPermanent
                        updated.durationHours = Int(durationHoursText) ?? originalItem.durationHours
                        updated.maxDevices = isSingleDevice ? 1 : 999
                        updated.boundDevice = boundDeviceText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if resetTimer {
                            updated.firstLoginAt = 0
                        }
                        updated.note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}
