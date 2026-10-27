// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation

func runBezierTests(directory:URL) throws {
    defer {try? FileManager.default.removeItem(at:directory)}
    var curve=BezierEnvelope.line(1,0)
    precondition(curve.valid)
    for i in 0...100 {let x=Double(i)/100;precondition(abs(curve.value(x)-(1-x))<0.000001)}
    curve.nodes[0].outgoing=CurvePoint(x:0.1,y:1)
    curve.nodes[1].incoming=CurvePoint(x:0.85,y:0.8)
    precondition(curve.valid && curve.value(0.5)>0.75)
    let samples=(0...100).map{curve.value(Double($0)/100)}
    for _ in 0..<10 {curve.splitLongest();precondition(curve.valid)}
    for i in 0...100 {precondition(abs(curve.value(Double(i)/100)-samples[i])<0.000001,"Inserting a point changed the curve")}
    var invalid=curve;invalid.nodes[1].point.x = .nan;precondition(!invalid.valid)
    invalid=curve;invalid.nodes[1].incoming.y=1.01;precondition(!invalid.valid)
    invalid=curve;invalid.nodes[0].outgoing.x=1;precondition(!invalid.valid)
    let pulse=BezierEnvelope.preset("Pulso");precondition(pulse.valid && abs(pulse.value(0.5)-1)<0.000001)
    let store=Store(recoveryStorage:RecoveryStorage(directory:directory),startTimer:false)
    store.setEnvelope(curve)
    precondition(store.project.version==5 && validate(store.project))
    precondition(abs(level(store.project,0.5)-curve.value(0.5))<0.000001)
    store.undoEdit();precondition(store.project.envelope=="Corte" && store.project.bezier==nil)
    store.redoEdit();precondition(store.project.bezier==curve)
    store.saveRecovery();let restored=Store(recoveryStorage:store.recovery,startTimer:false)
    precondition(restored.project.bezier==curve && restored.project.envelope=="Bézier")
    var old=demoProject();old.version=3
    let data=try JSONEncoder().encode(old),decoded=try JSONDecoder().decode(Project.self,from:data)
    precondition(validate(decoded) && decoded.bezier==nil)
    let bridgeDirectory=directory.appendingPathComponent("bridge")
    let bridge=LiveBridge(directory:bridgeDirectory);try bridge.prepare()
    bridge.send(project:store.project,selected:0,step:0,phase:0.37,playing:true,enabled:true){_ in}
    let file=bridgeDirectory.appendingPathComponent("frame.json"),end=Date().addingTimeInterval(2)
    while !FileManager.default.fileExists(atPath:file.path) && Date()<end {_=RunLoop.main.run(mode:.default,before:Date().addingTimeInterval(0.01))}
    let frame=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
    precondition(abs((frame["intensity"] as! Double)-curve.value(0.37))<0.000001)
    store.recoveryWork?.cancel();restored.recoveryWork?.cancel()
    print("PASS: Bezier interpolation, shape-preserving point insertion, validation, undo/redo, legacy projects, recovery and live bridge intensity")
}
