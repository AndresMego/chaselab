// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation
import CryptoKit

struct PluginComponent: Codable {
    let filename:String
    let name:String
    let id:String
    let bundleID:String
    let binary:String
    let sha256:String
}
enum PluginInstallError: LocalizedError {
    case invalid(String)
    var errorDescription:String? { if case .invalid(let message)=self {return message};return nil }
}
struct PluginInstallCore {
    static func info(_ url:URL)throws->[String:Any] {
        let data=try Data(contentsOf:url.appendingPathComponent("Contents/Info.plist"))
        guard let value=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else {throw PluginInstallError.invalid("Complemento inválido: \(url.lastPathComponent)")};return value
    }
    static func install(components:[PluginComponent],payload:URL,destination:URL,backups:URL)throws->URL {
        let fm=FileManager.default
        guard !components.isEmpty,Set(components.map(\.filename)).count==components.count else {throw PluginInstallError.invalid("La lista de complementos no es válida.")}
        // Validate everything before changing any installed bundle.
        for c in components {
            guard c.filename==URL(fileURLWithPath:c.filename).lastPathComponent,c.filename.hasSuffix(".bundle"),!c.filename.hasPrefix("."),c.binary==URL(fileURLWithPath:c.binary).lastPathComponent,!c.binary.isEmpty else {throw PluginInstallError.invalid("Nombre de complemento inválido.")}
            let source=payload.appendingPathComponent(c.filename),target=destination.appendingPathComponent(c.filename)
            guard try source.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else {throw PluginInstallError.invalid("No se admiten enlaces en el paquete.")}
            let properties=try info(source)
            guard properties["CFBundleIdentifier"] as? String==c.bundleID,properties["CFBundleExecutable"] as? String==c.binary else {throw PluginInstallError.invalid("Identidad inválida: \(c.name)")}
            let binary=source.appendingPathComponent("Contents/MacOS/"+c.binary)
            let hash=SHA256.hash(data:try Data(contentsOf:binary)).map{String(format:"%02x",$0)}.joined()
            guard hash==c.sha256 else {throw PluginInstallError.invalid("El archivo de \(c.name) no coincide con el paquete.")}
            if fm.fileExists(atPath:target.path) {
                guard try target.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true,try info(target)["CFBundleIdentifier"] as? String==c.bundleID else {throw PluginInstallError.invalid("Hay otro archivo llamado \(c.filename). No se reemplazó.")}
            }
        }
        try fm.createDirectory(at:destination,withIntermediateDirectories:true)
        let transaction=UUID().uuidString,backup=backups.appendingPathComponent(transaction,isDirectory:true)
        let staging=destination.appendingPathComponent(".chaselab-install-"+transaction,isDirectory:true)
        try fm.createDirectory(at:staging,withIntermediateDirectories:false)
        defer {try? fm.removeItem(at:staging)}
        var old:[String]=[],changed:[String]=[]
        for c in components {try fm.copyItem(at:payload.appendingPathComponent(c.filename),to:staging.appendingPathComponent(c.filename))}
        try fm.createDirectory(at:backup,withIntermediateDirectories:true)
        for c in components where fm.fileExists(atPath:destination.appendingPathComponent(c.filename).path) {
            try fm.copyItem(at:destination.appendingPathComponent(c.filename),to:backup.appendingPathComponent(c.filename));old.append(c.filename)
        }
        do {
            for c in components {
                let target=destination.appendingPathComponent(c.filename);changed.append(c.filename)
                if fm.fileExists(atPath:target.path){try fm.removeItem(at:target)}
                try fm.moveItem(at:staging.appendingPathComponent(c.filename),to:target)
            }
        }catch {
            var recoveryFailed=false
            for name in changed {
                let target=destination.appendingPathComponent(name)
                do {if fm.fileExists(atPath:target.path){try fm.removeItem(at:target)};if old.contains(name){try fm.copyItem(at:backup.appendingPathComponent(name),to:target)}}catch {recoveryFailed=true}
            }
            if recoveryFailed {throw PluginInstallError.invalid("No se completó la instalación. Tus copias están en \(backup.path).")}
            throw error
        }
        return backup
    }
}
