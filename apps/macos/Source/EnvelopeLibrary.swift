// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation
import SwiftUI

struct NamedEnvelope:Codable,Identifiable,Equatable {
    var id=UUID()
    var name:String
    var curve:BezierEnvelope
    static var smoothFade:BezierEnvelope {
        var c=BezierEnvelope.line(1,0)
        c.nodes[0].outgoing=CurvePoint(x:0.5,y:1)
        c.nodes[1].incoming=CurvePoint(x:0.5,y:0)
        return c
    }
    static var initial:[NamedEnvelope] {[NamedEnvelope(id:UUID(uuidString:"00000000-0000-0000-0000-000000000001")!,name:"Envolvente 1",curve:smoothFade)]}
    var valid:Bool {!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.count<=128 && curve.valid}
    static func validLibrary(_ entries:[Self])->Bool {
        (1...512).contains(entries.count) && Set(entries.map(\.id)).count==entries.count && entries.allSatisfy(\.valid)
    }
}
final class EnvelopeLibraryStorage {
    let directory:URL
    private var savedEntries:[NamedEnvelope]?
    init(directory:URL?=nil) {
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ChaseLab-Envelopes",isDirectory:true)
    }
    private func decoded(_ url:URL)->[NamedEnvelope]? {
        guard let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<4_000_000,
              let data=try? Data(contentsOf:url),let entries=try? JSONDecoder().decode([NamedEnvelope].self,from:data),NamedEnvelope.validLibrary(entries) else {return nil}
        return entries
    }
    func load()->[NamedEnvelope] {
        for name in ["library.json","library-previous.json"] {if let entries=decoded(directory.appendingPathComponent(name)){savedEntries=name=="library.json" ? entries:nil;return entries}}
        return NamedEnvelope.initial
    }
    func save(_ entries:[NamedEnvelope])throws {
        guard NamedEnvelope.validLibrary(entries) else {throw AppError.message("Biblioteca de envolventes inválida.")}
        if savedEntries==entries {return}
        let fm=FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let current=directory.appendingPathComponent("library.json")
        if let bytes=try? Data(contentsOf:current) {
            let target=decoded(current)==nil ? "library-corrupt-\(UUID().uuidString).json":"library-previous.json"
            try bytes.write(to:directory.appendingPathComponent(target),options:.atomic)
        }
        try JSONEncoder().encode(entries).write(to:current,options:.atomic)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:current.path);savedEntries=entries
    }
}
extension Store {
    var chosenLibraryIndex:Int? {selectedLibraryEnvelopeID.flatMap{id in envelopeLibrary.firstIndex{$0.id.uuidString==id}}}
    func reconcileLibrarySelection() {
        guard project.libraryEnvelopeID != nil else {return}
        guard let i=envelopeLibrary.firstIndex(where:{$0.id.uuidString==project.libraryEnvelopeID}) else {project.libraryEnvelopeID=nil;return}
        var p=project;p.envelope="Bézier";p.bezier=envelopeLibrary[i].curve;project=p
    }
    func selectLibraryEnvelope(_ id:String) {selectedLibraryEnvelopeID=id.isEmpty ? nil:id}
    func useLibraryEnvelopeInProject() {
        guard let i=chosenLibraryIndex else {return};recordEdit()
        project.libraryEnvelopeID=envelopeLibrary[i].id.uuidString;reconcileLibrarySelection()
    }
    func addLibraryEnvelope(copy:Bool=false) {
        guard envelopeLibrary.count<512 else {return}
        let currentCurve=editableEnvelope
        let name=copy ? "\(chosenLibraryIndex.map{envelopeLibrary[$0].name} ?? "Curva") copia":"Envolvente \(envelopeLibrary.count+1)"
        recordEdit()
        let entry=NamedEnvelope(name:name,curve:copy ? currentCurve:NamedEnvelope.smoothFade)
        envelopeLibrary.append(entry);selectedLibraryEnvelopeID=entry.id.uuidString
    }
    func renameLibraryEnvelope(_ name:String) {
        guard let i=chosenLibraryIndex,!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=128,name != envelopeLibrary[i].name else {return}
        recordEdit();var entries=envelopeLibrary;entries[i].name=name;envelopeLibrary=entries
    }
    func deleteLibraryEnvelope() {
        guard let i=chosenLibraryIndex else {return};recordEdit()
        if envelopeLibrary.count==1 {
            var entries=envelopeLibrary;entries[0].name="Envolvente 1";entries[0].curve=NamedEnvelope.smoothFade;envelopeLibrary=entries;reconcileLibrarySelection()
        } else {
            let removed=envelopeLibrary[i].id.uuidString;envelopeLibrary.remove(at:i);selectedLibraryEnvelopeID=nil
            // An explicitly linked project retains its embedded curve if the library item is deleted.
            if project.libraryEnvelopeID==removed {project.libraryEnvelopeID=nil}
        }
    }
    func moveLibraryEnvelope(_ direction:Int) {
        guard let i=chosenLibraryIndex,envelopeLibrary.indices.contains(i+direction) else {return};recordEdit()
        var entries=envelopeLibrary;entries.swapAt(i,i+direction);envelopeLibrary=entries
    }
}
private final class EnvelopeLibraryPanelState:ObservableObject {
    @Published var showPresets=false
}
struct EnvelopeLibraryPanel:View {
    @ObservedObject var store:Store
    @StateObject private var ui=EnvelopeLibraryPanelState()
    var body:some View {
        VStack(alignment:.leading,spacing:9) {
            Button("Curvas predefinidas…"){ui.showPresets=true}
            Text("BIBLIOTECA COMPARTIDA").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Picker("Envolvente de biblioteca",selection:Binding(get:{store.selectedLibraryEnvelopeID ?? ""},set:store.selectLibraryEnvelope)) {
                Text("Curva del proyecto").tag("")
                ForEach(store.envelopeLibrary) {entry in Text(entry.name).tag(entry.id.uuidString)}
            }.labelsHidden()
            if store.chosenLibraryIndex != nil {
                TextField("Nombre de envolvente",text:Binding(get:{store.chosenLibraryIndex.map{store.envelopeLibrary[$0].name} ?? ""},set:store.renameLibraryEnvelope)).textFieldStyle(.roundedBorder)
            }
            if store.chosenLibraryIndex != nil {Button("Usar en proyecto",action:store.useLibraryEnvelopeInProject)}
            HStack {
                Button {store.addLibraryEnvelope()} label:{Image(systemName:"plus")}.disabled(store.envelopeLibrary.count>=512).help("Crear envolvente").accessibilityLabel("Crear envolvente")
                Button {store.addLibraryEnvelope(copy:true)} label:{Image(systemName:"doc.on.doc")}.disabled(store.envelopeLibrary.count>=512).help("Duplicar curva actual").accessibilityLabel("Duplicar envolvente")
                Button {store.moveLibraryEnvelope(-1)} label:{Image(systemName:"arrow.up")}.disabled(store.chosenLibraryIndex==nil || store.chosenLibraryIndex==0).accessibilityLabel("Subir envolvente")
                Button {store.moveLibraryEnvelope(1)} label:{Image(systemName:"arrow.down")}.disabled(store.chosenLibraryIndex==nil || store.chosenLibraryIndex==store.envelopeLibrary.count-1).accessibilityLabel("Bajar envolvente")
                Button(action:store.deleteLibraryEnvelope) {Image(systemName:"trash")}.disabled(store.chosenLibraryIndex==nil).help("Eliminar · la última se restablece a una curva S").accessibilityLabel("Eliminar envolvente")
            }.disabled(store.envelopeLibrary.count>=512 && store.chosenLibraryIndex==nil)
            Text("La biblioteca se comparte entre proyectos. Seleccionar una curva no cambia el proyecto; Envelope en Arena elige la curva por instancia.").font(.caption).foregroundColor(.secondary)
        }.sheet(isPresented:$ui.showPresets){EnvelopePresetGallery(store:store,onClose:{ui.showPresets=false})}
    }
}
