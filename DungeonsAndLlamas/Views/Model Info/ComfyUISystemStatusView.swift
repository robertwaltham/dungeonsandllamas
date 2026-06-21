//
//  ComfyUISystemStatusView.swift
//  DungeonsAndLlamas
//
//  Created by OpenAI on 2026-06-21.
//

import SwiftUI

struct ComfyUISystemStatusView: View {
    let connection: ComfyUIClient.ConnectionInfo?
    let status: ComfyUIClient.SystemStatus?
    let error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("ComfyUI")
                    .font(.title)

                if let connection {
                    section("Connection") {
                        property("URL", connection.url)
                        property("Status", connection.statusCode.description)
                        property("Connected", connection.connected ? "Yes" : "No")
                    }
                }

                if let error {
                    section("Error") {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                if let status {
                    systemSection(status.system)
                    packageSection(status.system.comfyPackageVersions)
                    deviceSection(status.devices)
                } else if error == nil {
                    Text("No system status loaded.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(minWidth: 360, maxWidth: 520, alignment: .leading)
        }
    }

    private func systemSection(_ system: ComfyUIClient.SystemStatus.SystemInfo) -> some View {
        section("System") {
            property("OS", system.os)
            property("ComfyUI", system.comfyuiVersion)
            property("Python", system.pythonVersion)
            property("PyTorch", system.pytorchVersion)
            property("RAM", "\(formatBytes(system.ramFree)) free / \(formatBytes(system.ramTotal)) total")
            property("Frontend", "\(system.requiredFrontendVersion) required")
            property("Templates", "\(system.installedTemplatesVersion) installed / \(system.requiredTemplatesVersion) required")
            property("Embedded Python", system.embeddedPython ? "Yes" : "No")
            property("Environment", system.deployEnvironment)
            property("Arguments", system.argv.joined(separator: " "))
        }
    }

    private func packageSection(_ packages: [ComfyUIClient.SystemStatus.PackageVersion]) -> some View {
        section("Packages") {
            if packages.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(packages, id: \.name) { package in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(package.name)
                            .font(.headline)
                        Text("\(package.installed) installed / \(package.required) required")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func deviceSection(_ devices: [ComfyUIClient.SystemStatus.Device]) -> some View {
        section("Devices") {
            if devices.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices, id: \.index) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.headline)
                        property("Type", device.type)
                        property("Index", device.index.description)
                        property("VRAM", "\(formatBytes(device.vramFree)) free / \(formatBytes(device.vramTotal)) total")
                        property("Torch VRAM", "\(formatBytes(device.torchVramFree)) free / \(formatBytes(device.torchVramTotal)) total")
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func property(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(name)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}

#Preview {
    ComfyUISystemStatusView(connection: nil, status: nil, error: nil)
}
