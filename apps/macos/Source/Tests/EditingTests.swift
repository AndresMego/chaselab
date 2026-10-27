// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation

func runEditingTests(directory:URL) throws {
    let e=Store(recoveryStorage:RecoveryStorage(directory:directory),startTimer:false)
    defer { e.recoveryWork?.cancel() }
    e.pattern("Vaciar")
    let before=e.project.sequences[0].cells,history=e.undoStates.count
    e.paint(GridCell(row:0,column:0));e.paint(GridCell(row:0,column:6));e.paint(GridCell(row:0,column:2));e.endPaint()
    precondition((0...6).allSatisfy { e.project.sequences[0].cells[0][$0] })
    precondition(e.undoStates.count==history+1,"A stroke is one undo transaction")
    e.undoEdit();precondition(e.project.sequences[0].cells==before)
    e.redoEdit();e.paint(GridCell(row:0,column:0));e.paint(GridCell(row:0,column:6));e.endPaint()
    precondition((0...6).allSatisfy { !e.project.sequences[0].cells[0][$0] })
    e.undoEdit();precondition(e.project.sequences[0].cells[0][6])
    precondition(GridLayout.cell(x:124,y:0,rows:8,columns:16)==GridCell(row:0,column:0))
    precondition(GridLayout.cell(x:154,y:0,rows:8,columns:16)==nil)
    precondition(GridLayout.cell(x:158,y:29,rows:8,columns:16)==GridCell(row:1,column:1))
    precondition(GridLayout.cell(x:123,y:0,rows:8,columns:16)==nil)
    precondition(GridLayout.cell(x:Double.infinity,y:0,rows:8,columns:16)==nil)

    e.pattern("Vaciar");e.toggle(0,1);e.toggle(3,1);e.selectEditStep(1);e.setStepDuration(2);e.copyStep()
    e.selectEditStep(5);e.pasteStep()
    precondition(e.project.sequences[0].cells.map { $0[5] }==e.project.sequences[0].cells.map { $0[1] })
    precondition(e.timing.weights[5]==2)
    e.undoEdit();precondition(e.timing.weights[5]==1 && !e.project.sequences[0].cells[0][5]);e.redoEdit()
    e.addSequence(copy:false);e.selectEditStep(2);e.pasteStep()
    precondition(e.timing.weights[2]==2 && e.project.sequences[1].cells[3][2])
    e.selectEditStep(0);e.setStepDuration(0.25)
    let durations=e.timing.weights
    e.transform("Reversa");e.transform("Reversa");precondition(e.timing.weights==durations)
    e.transform("Desplazar izquierda");e.transform("Desplazar derecha");precondition(e.timing.weights==durations)
    e.resize(4);let short=e.timing.weights;e.resize(8)
    precondition(Array(e.timing.weights.prefix(4))==short && e.timing.weights.suffix(4).allSatisfy {$0==1})

    let preserved=e.project.sequences[e.selected].cells,weights=e.timing.weights
    e.resize(9);precondition(e.count==9 && e.timing.weights.last==1 && e.project.sequences[e.selected].cells.allSatisfy{!$0[8]})
    precondition(e.project.sequences[e.selected].cells.map{Array($0.prefix(8))}==preserved && Array(e.timing.weights.prefix(8))==weights)
    e.selectEditStep(8);e.resize(8);precondition(e.editStep==7 && e.step<8)
    e.undoEdit();precondition(e.count==9 && e.editStep==8);e.redoEdit();precondition(e.count==8)
    e.resize(1);e.resize(0);precondition(e.count==1);e.resize(256);e.resize(257);precondition(e.count==256 && validate(e.project))
    print("PASS: single-step add/remove, content and duration preservation, selection clamp, undo and 1...256 limits")

    var p=demoProject();p.sequences[0].cells=p.slices.map { _ in [true,false,true,false] };p.sequences[0].durations=[0.5,2,1,4]
    let timing=SequenceTiming(p.sequences[0])
    precondition(timing.total==7.5 && timing.offset(2)==2.5)
    precondition(timing.location(0.49).step==0 && timing.location(0.5).step==1 && timing.location(2.5).step==2)
    precondition(abs(timing.location(2.25).phase-0.875)<0.00001 && timing.location(7.5).step==0)
    precondition(timing.location(-0.01).step==3)
    e.selected=0;e.editStep=0;e.project=p;e.step=1;e.phase=0.75;e.tempoChanged()
    precondition(abs((ProcessInfo.processInfo.systemUptime-e.anchor)/e.duration-2)<0.01)
    e.project.bpm=240;e.tempoChanged()
    precondition(abs((ProcessInfo.processInfo.systemUptime-e.anchor)/e.duration-2)<0.01)
    e.playing=true;e.anchor=ProcessInfo.processInfo.systemUptime-2.25*e.duration;e.tick()
    precondition(e.step==1 && abs(e.phase-0.875)<0.02)
    let playhead=e.step;e.selectEditStep(3);precondition(e.step==playhead && e.editStep==3)
    var clock=ArenaClock();clock.receive(bpm:60,barPhase:0.5,time:100,now:100)
    let hostPosition=clock.position(at:100,division:2,count:4,cycleLength:timing.total)!
    precondition(timing.location(hostPosition).step==3)

    var bad=p;bad.sequences[0].durations=[1];precondition(!validate(bad))
    bad=p;bad.sequences[0].durations=[0,1,1,1];precondition(!validate(bad))
    bad=p;bad.sequences[0].durations=[Double.nan,1,1,1];precondition(!validate(bad))
    let decoded=try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p));precondition(decoded.sequences[0].durations==[0.5,2,1,4])
    var legacy=demoProject();legacy.version=1
    let old=try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(legacy))
    precondition(validate(old) && SequenceTiming(old.sequences[0]).weights.allSatisfy {$0==1})
    e.project=demoProject();e.editStep=0;precondition(!e.canPasteStep)
    print("PASS: drag painting/erasing, single-stroke undo, step clipboard, duration timing/export model, legacy projects")
}
