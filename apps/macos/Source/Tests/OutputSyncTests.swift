// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation
func runOutputSyncTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("output-sync-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    try FileManager.default.createDirectory(at:directory.appendingPathComponent("Preferences"),withIntermediateDirectories:true)
    let sync=ArenaOutputSync(root:directory)
    let prefs=directory.appendingPathComponent("Preferences/AdvancedOutput.xml")
    try Data("<ScreenSetup presetFile='Kiki'/>".utf8).write(to:prefs)
    let active=try sync.activeURL();precondition(active.lastPathComponent=="Kiki.xml")
    try Data("<ScreenSetup presetFile='../elsewhere'/>".utf8).write(to:prefs)
    var rejected=false;do {_=try sync.activeURL()}catch{rejected=true};precondition(rejected)
    var p=demoProject();p.sequences[0].durations=Array(repeating:2,count:16)
    for i in p.slices.indices {p.slices[i].sourceID="id\(i)"}
    var newer=Array(p.slices.reversed());newer[0].name="Renombrado";newer[0].points[0].x+=10
    let mount=ArenaMount(name:"Test.xml",width:p.width,height:p.height,slices:newer)
    let merged=try ArenaOutputSync.merge(p,mount)
    precondition(merged.slices[0].id==p.slices[7].id && merged.sequences[0].cells[0]==p.sequences[0].cells[7])
    precondition(merged.sequences[0].durations==p.sequences[0].durations)
    var legacy=p;for i in legacy.slices.indices {legacy.slices[i].sourceID=nil}
    let linked=try ArenaOutputSync.merge(legacy,ArenaMount(name:"Test.xml",width:p.width,height:p.height,slices:p.slices))
    precondition(linked.slices.map(\.id)==legacy.slices.map(\.id) && linked.sequences[0].cells==legacy.sequences[0].cells)
    newer.removeLast();var added=newer[0];added.id=UUID();added.sourceID="new";added.name="Nuevo";newer.append(added)
    let changed=try ArenaOutputSync.merge(p,ArenaMount(name:"Test.xml",width:p.width,height:p.height,slices:newer))
    precondition(changed.sequences[0].cells.last!.allSatisfy{!$0})
    legacy.slices[1].name=legacy.slices[0].name;rejected=false
    do {_=try ArenaOutputSync.merge(legacy,ArenaMount(name:"Test.xml",width:p.width,height:p.height,slices:p.slices))}catch{rejected=true};precondition(rejected)
    let store=Store(recoveryStorage:RecoveryStorage(directory:directory.appendingPathComponent("recovery")),startTimer:false);store.project=p
    try store.applyArenaMount(mount);store.undoEdit()
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    let restored=try encoder.encode(store.project),original=try encoder.encode(p);precondition(restored==original)
    let snapshots=try FileManager.default.contentsOfDirectory(atPath:store.recovery.directory.appendingPathComponent("Snapshots").path);precondition(!snapshots.isEmpty)
    store.recoveryWork?.cancel()
    let presetDir=directory.appendingPathComponent("Presets/Advanced Output")
    try FileManager.default.createDirectory(at:presetDir,withIntermediateDirectories:true)
    let file=presetDir.appendingPathComponent("Watch.xml")
    func writePreset(_ x:Int) throws {
        let xml="<root><CurrentCompositionTextureSize width='100' height='100'/><Screen uniqueId='s'><Slice uniqueId='1'><Params name='Common'><Param name='Name' value='A'/></Params><InputRect><v x='\(x)' y='0'/><v x='30' y='0'/><v x='0' y='30'/></InputRect></Slice><Slice uniqueId='2'><Params name='Common'><Param name='Name' value='B'/></Params><InputRect><v x='50' y='0'/><v x='80' y='0'/><v x='50' y='30'/></InputRect></Slice></Screen></root>"
        try Data(xml.utf8).write(to:file,options:.atomic)
    }
    func waitFor(_ condition:()->Bool) {
        let end=Date().addingTimeInterval(3)
        while !condition() && Date()<end {_=RunLoop.main.run(mode:.default,before:Date().addingTimeInterval(0.01))}
        precondition(condition(),"Output watcher failed to finish")
    }
    try Data("<ScreenSetup presetFile='Watch'/>".utf8).write(to:prefs);try writePreset(0)
    let watcher=ArenaOutputSync(root:directory),initial=try watcher.load()
    let live=Store(recoveryStorage:RecoveryStorage(directory:directory.appendingPathComponent("watch-recovery")),startTimer:false)
    live.project=Project(width:100,height:100,arenaPreset:initial.name,slices:initial.slices,sequences:[Sequence(name:"Keep",cells:[[true,false],[false,true]])]);live.syncOutput=true
    watcher.check(store:live);waitFor{live.outputSyncStatus.contains("Sincronizado")}
    try writePreset(9);watcher.check(store:live);waitFor{live.project.slices[0].points[0].x==9}
    precondition(live.project.sequences[0].cells==[[true,false],[false,true]])
    try Data("<invalid".utf8).write(to:file,options:.atomic);watcher.check(store:live);waitFor{!live.syncOutput}
    precondition(live.project.slices[0].points[0].x==9)
    live.recoveryWork?.cancel()
    print("PASS: asynchronous saved-output watcher applies valid updates and preserves the last project on invalid XML")
    print("PASS: active Arena preset detection, path safety, slice ID/reorder/rename matching, legacy linking, added/deleted slices, durations, ambiguity rejection, backup and undo")
}
