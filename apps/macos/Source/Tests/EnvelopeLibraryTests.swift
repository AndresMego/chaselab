// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation
func runEnvelopeLibraryTests()throws {
    let temp=FileManager.default.temporaryDirectory.appendingPathComponent("chaselab-library-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:temp)}
    let storage=RecoveryStorage(directory:temp.appendingPathComponent("session"))
    let store=Store(recoveryStorage:storage,startTimer:false)
    defer{store.recoveryWork?.cancel()}
    precondition(store.envelopeLibrary.count==1 && store.envelopeLibrary[0].curve.valid && store.selectedLibraryEnvelopeID==nil)
    let original=store.project.sequences
    let projectEncoder=JSONEncoder();projectEncoder.outputFormatting=[.sortedKeys];let untouchedProject=try projectEncoder.encode(store.project)
    store.addLibraryEnvelope();precondition(store.envelopeLibrary.count==2 && store.chosenLibraryIndex==1)
    store.renameLibraryEnvelope("Golpe");store.setEnvelope(.line(1,0));precondition(store.envelopeLibrary[1].name=="Golpe")
    store.addLibraryEnvelope(copy:true);precondition(store.envelopeLibrary.count==3 && store.envelopeLibrary[2].curve==store.envelopeLibrary[1].curve)
    let id=store.selectedLibraryEnvelopeID;store.moveLibraryEnvelope(-1);precondition(store.selectedLibraryEnvelopeID==id && store.chosenLibraryIndex==1)
    store.deleteLibraryEnvelope();precondition(store.envelopeLibrary.count==2 && store.selectedLibraryEnvelopeID==nil)
    store.undoEdit();precondition(store.envelopeLibrary.count==3 && store.selectedLibraryEnvelopeID==id)
    store.redoEdit();precondition(store.envelopeLibrary.count==2)
    store.saveRecovery();let reopened=Store(recoveryStorage:storage,startTimer:false);defer{reopened.recoveryWork?.cancel()}
    precondition(reopened.envelopeLibrary==store.envelopeLibrary)
    // A new document uses the same library independently of its project content.
    reopened.project=demoProject();precondition(reopened.envelopeLibrary.count==2)
    let encoded=try LiveBridge.catalogData(project:store.project,session:"library",revision:1,envelopes:store.envelopeLibrary)
    let catalog=try JSONSerialization.jsonObject(with:encoded) as! [String:Any],entries=catalog["envelopes"] as! [[String:Any]]
    precondition(entries.count==2 && (entries[1]["values"] as! [Double]).count==1025)
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let before=try encoder.encode(original),after=try encoder.encode(store.project.sequences);precondition(before==after)
    let managedProject=try projectEncoder.encode(store.project);precondition(managedProject==untouchedProject,"Managing the shared library changed the project")
    store.selectLibraryEnvelope(store.envelopeLibrary[0].id.uuidString);store.useLibraryEnvelopeInProject()
    precondition(store.project.libraryEnvelopeID==store.envelopeLibrary[0].id.uuidString)
    store.setEnvelope(.line(0,1));precondition(store.project.bezier==store.envelopeLibrary[0].curve)
    var invalid=NamedEnvelope.initial;invalid.append(invalid[0]);precondition(!NamedEnvelope.validLibrary(invalid))
    let library=EnvelopeLibraryStorage(directory:temp.appendingPathComponent("corrupt"));try library.save(NamedEnvelope.initial)
    var changed=NamedEnvelope.initial;changed[0].name="Guardada";try library.save(changed)
    try Data("broken".utf8).write(to:library.directory.appendingPathComponent("library.json"));precondition(library.load()==NamedEnvelope.initial)
    store.envelopeLibrary=NamedEnvelope.initial;store.selectLibraryEnvelope(store.envelopeLibrary[0].id.uuidString);store.setEnvelope(.line(0,1));store.deleteLibraryEnvelope()
    precondition(store.envelopeLibrary.count==1 && store.envelopeLibrary[0].curve==NamedEnvelope.smoothFade)
    print("PASS: shared named envelope library create/rename/duplicate/reorder/delete, last reset, undo/redo, persistence, project independence, catalog LUT and corrupt fallback")
}
