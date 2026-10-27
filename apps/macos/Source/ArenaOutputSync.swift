// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation
import AppKit

struct ArenaMount {
    var name:String;var width:Double;var height:Double;var slices:[Slice]
}
final class ArenaOutputSync {
    let root:URL
    private var busy=false
    private var fingerprint=""
    init(root:URL?=nil) {self.root=root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Resolume Arena")}
    func reset(){fingerprint=""}
    func activeURL() throws -> URL {
        let path=root.appendingPathComponent("Preferences/AdvancedOutput.xml")
        guard (try path.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<1_000_000 else {throw AppError.message("Referencia de Advanced Output demasiado grande.")}
        let doc=try XMLDocument(contentsOf:path,options:[.nodeLoadExternalEntitiesNever])
        guard let name=(try doc.nodes(forXPath:"//ScreenSetup/@presetFile").first?.stringValue),!name.isEmpty,!name.hasPrefix("."),!name.contains("/"),!name.contains("\\") else {throw AppError.message("Arena no indica un preset guardado. Guarda Advanced Output con Save & Close.")}
        return root.appendingPathComponent("Presets/Advanced Output").appendingPathComponent(name.hasSuffix(".xml") ? name:name+".xml")
    }
    func load() throws -> ArenaMount {
        let url=try activeURL(),(w,h,slices)=try loadSlices(url)
        let ids=slices.compactMap(\.sourceID)
        guard Set(ids).count==ids.count else {throw AppError.message("El preset contiene identificadores de slices repetidos; se conserva el montaje anterior.")}
        return ArenaMount(name:url.lastPathComponent,width:w,height:h,slices:slices)
    }
    static func merge(_ project:Project,_ mount:ArenaMount) throws -> Project {
        let old=project.slices
        let oldIDs=Dictionary(grouping:old.indices.filter{old[$0].sourceID != nil},by:{old[$0].sourceID!})
        let oldNames=Dictionary(grouping:old.indices,by:{old[$0].name})
        let newNames=Dictionary(grouping:mount.slices.indices,by:{mount.slices[$0].name})
        var rows:[Int?]=[],slices=mount.slices,used=Set<Int>()
        for i in slices.indices {
            var match:Int?
            if let id=slices[i].sourceID,let candidates=oldIDs[id] {
                guard candidates.count==1 else {throw AppError.message("Identificadores ambiguos; no se modificó el proyecto.")};match=candidates[0]
            } else if let candidates=oldNames[slices[i].name],candidates.contains(where:{old[$0].sourceID==nil}) {
                guard candidates.count==1,newNames[slices[i].name]?.count==1 else {throw AppError.message("Hay nombres duplicados sin identificar. Renombra los slices antes de vincular.")}
                match=candidates[0]
            }
            if let j=match {
                guard !used.contains(j) else {throw AppError.message("No se puede relacionar un slice dos veces.")}
                used.insert(j);slices[i].id=old[j].id
            }
            rows.append(match)
        }
        var result=project;result.version=5;result.width=mount.width;result.height=mount.height;result.slices=slices;result.arenaPreset=mount.name
        for i in result.sequences.indices {
            let original=project.sequences[i].cells,count=original[0].count
            result.sequences[i].cells=rows.map {r in r.map{original[$0]} ?? Array(repeating:false,count:count)}
        }
        guard validate(result) else {throw AppError.message("El montaje actualizado no es válido; se conserva el anterior.")}
        return result
    }
    func check(store:Store) {
        guard !busy else {return};busy=true
        DispatchQueue.global(qos:.utility).async { [self,weak store] in
            let result:Result<(String,ArenaMount?),Error>
            do {
                let url=try activeURL(),prefs=root.appendingPathComponent("Preferences/AdvancedOutput.xml")
                let a=try url.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey]),b=try prefs.resourceValues(forKeys:[.contentModificationDateKey])
                let key="\(url.path)|\(a.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(a.fileSize ?? 0)|\(b.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                // The last fingerprint is only accessed on the main queue below.
                result = .success((key,nil))
            } catch {result = .failure(error)}
            DispatchQueue.main.async { [self,weak store] in
                guard let store,store.syncOutput else {busy=false;return}
                switch result {
                case .failure(let error):busy=false;store.syncOutput=false;store.outputSyncStatus="Sin actualizar: \(error.localizedDescription)"
                case .success(let (key,_)):
                    guard key != fingerprint else {busy=false;return}
                    DispatchQueue.global(qos:.utility).async { [self,weak store] in
                        let mount=Result{try load()}
                        DispatchQueue.main.async { [self,weak store] in
                            defer {busy=false}
                            guard let store,store.syncOutput else {return}
                            do {
                                let value=try mount.get()
                                guard store.project.arenaPreset==value.name else {store.syncOutput=false;store.outputSyncStatus="Arena cambió a \(value.name). Pulsa Detectar para vincularlo.";return}
                                try store.applyArenaMount(value);fingerprint=key
                            } catch {store.syncOutput=false;store.outputSyncStatus="Sin actualizar: \(error.localizedDescription)"}
                        }
                    }
                }
            }
        }
    }
}
extension Store {
    func applyArenaMount(_ mount:ArenaMount) throws {
        let merged=try ArenaOutputSync.merge(project,mount)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        guard try encoder.encode(merged) != encoder.encode(project) else {outputSyncStatus="Sincronizado · \(mount.slices.count) slices";return}
        try preserveBeforeReplace();recordEdit();project=merged
        outputSyncStatus="Actualizado · \(mount.slices.count) slices · puedes deshacer"
    }
    func linkArenaOutput() {
        do {
            let mount=try arenaOutput.load();_ = try ArenaOutputSync.merge(project,mount)
            let alert=NSAlert();alert.messageText="Vincular \(mount.name)"
            alert.informativeText="\(mount.slices.count) slices · \(Int(mount.width)) × \(Int(mount.height)). Se conservarán secuencias y duraciones. Los slices nuevos empezarán apagados; se guardará una copia antes de aplicar cambios. Se actualizará al guardar Advanced Output."
            alert.addButton(withTitle:"Vincular y sincronizar");alert.addButton(withTitle:"Cancelar")
            guard alert.runModal() == .alertFirstButtonReturn else {return}
            try applyArenaMount(mount);arenaOutput.reset();syncOutput=true
        } catch {fail(error)}
    }
}
