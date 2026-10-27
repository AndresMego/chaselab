// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation

struct SessionSnapshot:Codable {
    var project:Project
    var selected:Int
    var step:Int
    var followArenaBpm:Bool
    var savedAt:Date
    var followArenaPhase:Bool? = nil
    var editStep:Int? = nil
    func isValid()->Bool {
        validate(project) && project.sequences.indices.contains(selected) && (editStep == nil || (0..<(project.sequences[selected].cells.first?.count ?? 0)).contains(editStep!)) && (0..<(project.sequences[selected].cells.first?.count ?? 0)).contains(step)
    }
}
/// Separate recovery files never overwrite the user's explicit project file.
final class RecoveryStorage {
    let directory:URL
    let legacyDirectory:URL?
    init(directory:URL?=nil) {
        let base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        self.directory=directory ?? base.appendingPathComponent("ChaseLab-v5",isDirectory:true)
        self.legacyDirectory=directory == nil ? base.appendingPathComponent("ChaseLab-v4",isDirectory:true):nil
    }
    func load()->SessionSnapshot? {
        for source in [directory,legacyDirectory].compactMap({$0}) {
        for name in ["recovery.json","recovery-previous.json"] {
            let url=source.appendingPathComponent(name)
            guard let data=try? Data(contentsOf:url),data.count<20_000_000,let snapshot=try? JSONDecoder().decode(SessionSnapshot.self,from:data),snapshot.isValid() else { continue }
            return snapshot
        }
        }
        return nil
    }
    func save(_ snapshot:SessionSnapshot) throws {
        guard snapshot.isValid() else { throw AppError.message("No se puede guardar un proyecto inválido.") }
        let fm=FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let current=directory.appendingPathComponent("recovery.json")
        if let old=try? Data(contentsOf:current),let previous=try? JSONDecoder().decode(SessionSnapshot.self,from:old),previous.isValid() {
            try old.write(to:directory.appendingPathComponent("recovery-previous.json"),options:.atomic)
        }
        try JSONEncoder().encode(snapshot).write(to:current,options:.atomic)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:current.path)
    }
    func preserve(_ snapshot:SessionSnapshot) throws {
        let history=directory.appendingPathComponent("Snapshots",isDirectory:true)
        try FileManager.default.createDirectory(at:history,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let stamp=ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")
        let url=history.appendingPathComponent("ChaseLab-\(stamp)-\(UUID().uuidString.prefix(6)).chaselab")
        try JSONEncoder().encode(snapshot.project).write(to:url,options:.atomic)
    }
}
