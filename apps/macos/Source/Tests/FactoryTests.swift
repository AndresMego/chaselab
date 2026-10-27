// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation

func runFactoryTests(directory:URL) throws {
    defer { try? FileManager.default.removeItem(at:directory) }
    let slices=(0..<6).map { i -> Slice in
        let x=Double(i%3)*100,y=Double(i/3)*100
        return Slice(name:"F\(i)",points:[Point(x:x,y:y),Point(x:x+40,y:y),Point(x:x+40,y:y+40),Point(x:x,y:y+40)])
    }
    var f=FactorySettings.automatic(slices)
    precondition(f.x.count==2 && f.y.count==1)
    func active(_ result:FactoryResult,_ step:Int)->[Int] { result.cells.indices.filter{result.cells[$0][step]} }
    var result=FactoryEngine.generate(slices,f)
    precondition(result.steps==6 && active(result,0)==[0] && active(result,3)==[3])
    f.direction="Vertical";result=FactoryEngine.generate(slices,f)
    precondition(active(result,1)==[3] && active(result,2)==[1])
    f.direction="Filas";result=FactoryEngine.generate(slices,f);precondition(result.steps==2 && active(result,0)==[0,1,2])
    f.direction="Columnas";result=FactoryEngine.generate(slices,f);precondition(result.steps==3 && active(result,1)==[1,4])
    f.direction="Horizontal";f.flipX=true;result=FactoryEngine.generate(slices,f);precondition(active(result,0)==[2]);f.flipX=false
    f.flipY=true;result=FactoryEngine.generate(slices,f);precondition(active(result,0)==[3]);f.flipY=false
    f.block=2;result=FactoryEngine.generate(slices,f);precondition(result.steps==3 && active(result,0)==[0,1]);f.block=1
    f.modulo=2;result=FactoryEngine.generate(slices,f);precondition(result.steps==2 && active(result,0)==[0,2,4]);f.modulo=0
    f.mirrorX=true;result=FactoryEngine.generate(slices,f);precondition(active(result,0)==[0,2]);f.mirrorY=true
    result=FactoryEngine.generate(slices,f);precondition(active(result,0)==[0,2,3,5]);f.mirrorX=false;f.mirrorY=false
    f.direction="Aleatorio";result=FactoryEngine.generate(slices,f)
    precondition(result.cells.allSatisfy{$0.filter{$0}.count==1});precondition(result.cells==FactoryEngine.generate(slices,f).cells)
    f.shuffle=true;result=FactoryEngine.generate(slices,f);precondition(result.cells.allSatisfy{$0.filter{$0}.count==1})
    f.x=[];f.y=[];f.direction="Filas";result=FactoryEngine.generate(slices,f);precondition(result.steps==1 && active(result,0).count==6)
    let store=Store(recoveryStorage:RecoveryStorage(directory:directory),startTimer:false)
    store.project=Project(slices:slices,sequences:[Sequence(name:"Original",cells:slices.map{_ in [false,false,false,false]})])
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let before=try encoder.encode(store.project)
    store.updateFactory(FactorySettings.automatic(slices));precondition(store.count==6 && validate(store.project))
    store.undoEdit();let restored=try encoder.encode(store.project);precondition(restored==before)
    store.redoEdit();precondition(store.count==6)
    store.addSequence(copy:true);precondition(store.project.sequences[1].factory==store.project.sequences[0].factory)
    store.saveRecovery();let loaded=Store(recoveryStorage:store.recovery,startTimer:false);precondition(loaded.count==6 && loaded.factory==store.factory)
    var clock=ArenaClock();clock.receive(bpm:120,barPhase:0.9,time:10,now:10)
    precondition(clock.position(at:10.1,division:4,count:6,cycleLength:6) != nil)
    precondition(clock.position(at:10.1,division:4,count:1,cycleLength:1) != nil)
    print("PASS: Factory spatial order, rows/columns, flips, block, modulo, mirrors, shuffle, editable grid, arbitrary lengths, undo and recovery")
}
