// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import AppKit
import Foundation

final class PluginInstaller {
    static func run() {
        do {
            let running=NSWorkspace.shared.runningApplications.contains{$0.bundleIdentifier=="com.resolume.arena" || $0.bundleIdentifier=="com.resolume.avenue"}
            guard !running else {throw PluginInstallError.invalid("Guarda tu composición y cierra Resolume antes de instalar o actualizar los efectos. Después vuelve a esta opción.")}
            guard let resources=Bundle.main.resourceURL else {throw PluginInstallError.invalid("No se encontró el paquete de efectos.")}
            let components=try JSONDecoder().decode([PluginComponent].self,from:Data(contentsOf:resources.appendingPathComponent("plugins.json")))
            let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true;panel.allowsMultipleSelection=false
            panel.message="Selecciona la carpeta Extra Effects de Resolume Arena. Tus proyectos y presets se conservarán."
            panel.prompt="Usar esta carpeta";panel.directoryURL=docs.appendingPathComponent("Resolume Arena/Extra Effects")
            guard panel.runModal() == .OK,let root=panel.url else {return}
            let destination=root.appendingPathComponent(FileManager.default.fileExists(atPath:root.appendingPathComponent("ChaseLab Live").path) ? "ChaseLab Live":"ChaseLab",isDirectory:true)
            let confirm=NSAlert();confirm.messageText="Instalar efectos de ChaseLab";confirm.informativeText="Se instalarán \(components.count) efectos en \(destination.path). Las versiones anteriores de estos mismos archivos quedarán respaldadas fuera de la carpeta de Arena."
            confirm.addButton(withTitle:"Instalar");confirm.addButton(withTitle:"Cancelar");guard confirm.runModal() == .alertFirstButtonReturn else {return}
            let backups=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ChaseLab-Installer/Backups",isDirectory:true)
            let backup=try PluginInstallCore.install(components:components,payload:resources.appendingPathComponent("Plugins"),destination:destination,backups:backups)
            let alert=NSAlert();alert.messageText="Efectos instalados";alert.informativeText="Abre Arena y busca CL Player, CL Bumper, CL Outliner, CL Wiper o CL Random. La fuente se llama CL Outline Src.\nCopias: \(backup.path)";alert.runModal()
        }catch {let alert=NSAlert();alert.messageText="No se instalaron los efectos";alert.informativeText=error.localizedDescription;alert.runModal()}
    }
}
