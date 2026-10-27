// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import SwiftUI

/// Visual interpretations of the user's reference; no original preset data is imported.
enum EnvelopePresets {
    static let names=["Default","4 To The Floor","ADSR","ASR","Digital","EasyEase","Jaws","LFO","Noise","Saw","Up N Down"]
    static func polygon(_ points:[CurvePoint])->BezierEnvelope {
        var nodes=points.map{CurveNode(point:$0,incoming:$0,outgoing:$0)}
        for i in 0..<points.count-1 {
            nodes[i].outgoing=points[i].mixed(points[i+1],1/3)
            nodes[i+1].incoming=points[i].mixed(points[i+1],2/3)
        }
        return BezierEnvelope(nodes:nodes)
    }
    static func curve(_ name:String)->BezierEnvelope {
        func p(_ x:Double,_ y:Double)->CurvePoint {CurvePoint(x:x,y:y)}
        func poly(_ pairs:[(Double,Double)])->BezierEnvelope {polygon(pairs.map{p($0.0,$0.1)})}
        func rounded(_ pairs:[(Double,Double)])->BezierEnvelope {
            var c=poly(pairs)
            for i in 0..<c.nodes.count-1 {
                let a=c.nodes[i].point,b=c.nodes[i+1].point
                c.nodes[i].outgoing=p(a.x+(b.x-a.x)*0.5,a.y)
                c.nodes[i+1].incoming=p(a.x+(b.x-a.x)*0.5,b.y)
            }
            return c
        }
        switch name {
        case "Default":return .line(0,1)
        case "EasyEase":return rounded([(0,0),(1,1)])
        case "Up N Down":return poly([(0,0),(0.5,1),(1,0)])
        case "LFO":return rounded([(0,1),(0.25,0),(0.5,1),(0.75,0),(1,1)])
        case "Digital":return poly([(0,1),(0.2498,1),(0.25,0),(0.4998,0),(0.5,1),(0.7498,1),(0.75,0),(0.9998,0),(1,1)])
        case "Saw","4 To The Floor":
            var pts=[p(0,1)]
            for i in 1...4 {let x=Double(i)/4;pts.append(p(i==4 ? x:x-0.0002,0));if i<4 {pts.append(p(x,1))}}
            var c=polygon(pts)
            if name=="4 To The Floor" {
                for i in stride(from:0,to:c.nodes.count-1,by:2) {
                    let a=c.nodes[i].point,b=c.nodes[i+1].point,d=b.x-a.x
                    c.nodes[i].outgoing=p(a.x+d*0.25,0.35);c.nodes[i+1].incoming=p(a.x+d*0.55,0)
                }
            }
            return c
        case "ADSR":
            var c=rounded([(0,0),(0.09,1),(0.15,0.78),(0.70,0.78),(1,0)])
            c.nodes[0].outgoing=p(0.025,0.85);c.nodes[1].incoming=p(0.055,1)
            c.nodes[3].outgoing=p(0.72,0.15);c.nodes[4].incoming=p(0.85,0)
            return c
        case "ASR":
            var c=rounded([(0,0),(0.09,1),(0.5,1),(1,0)])
            c.nodes[0].outgoing=p(0.015,0.85);c.nodes[1].incoming=p(0.04,1)
            c.nodes[2].outgoing=p(0.53,0.18);c.nodes[3].incoming=p(0.8,0)
            return c
        case "Jaws":
            var c=rounded([(0,1),(0.25,0),(0.5,1),(0.75,0),(1,1)])
            for i in 0..<4 {
                let a=c.nodes[i].point,b=c.nodes[i+1].point,d=b.x-a.x
                c.nodes[i].outgoing=p(a.x+d*0.88,a.y);c.nodes[i+1].incoming=p(a.x+d*0.98,b.y)
            }
            return c
        case "Noise":
            // Fixed seed: the pattern stays identical after save/reopen and on every step.
            var seed:UInt64=0x43484153454C4142
            let pts=(0..<64).map{i -> CurvePoint in
                seed=seed &* 6364136223846793005 &+ 1442695040888963407
                return p(Double(i)/63,0.06+Double((seed >> 32) & 65535)/65535*0.88)
            }
            return polygon(pts)
        default:return .line(1,0)
        }
    }
}
extension Store {
    func addEnvelopePresets(_ names:[String]) {
        let missing=names.filter{name in EnvelopePresets.names.contains(name) && !envelopeLibrary.contains(where:{$0.name==name})}
        guard !missing.isEmpty else {return}
        recordEdit()
        var entries=envelopeLibrary
        for name in missing where entries.count<512 {entries.append(NamedEnvelope(name:name,curve:EnvelopePresets.curve(name)))}
        envelopeLibrary=entries
        if let name=missing.first {selectedLibraryEnvelopeID=entries.first(where:{$0.name==name})?.id.uuidString}
    }
}
struct EnvelopePresetGallery:View {
    @ObservedObject var store:Store
    var onClose:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Text("Curvas predefinidas").font(.title2);Spacer();Button("Listo"){onClose()}.keyboardShortcut(.cancelAction)}
            Text("Añade una curva a la biblioteca sin cambiar la del proyecto. Los nombres existentes se conservan.").font(.caption).foregroundColor(.secondary)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:3),spacing:10) {
                ForEach(EnvelopePresets.names,id:\.self){name in
                    Button {store.addEnvelopePresets([name]);onClose()} label:{
                        VStack(alignment:.leading,spacing:8){
                            HStack {Text(name).font(.headline);Spacer();if store.envelopeLibrary.contains(where:{$0.name==name}){Image(systemName:"checkmark")}}
                            GeometryReader {g in
                                Path {path in
                                    let c=EnvelopePresets.curve(name)
                                    func pt(_ p:CurvePoint)->CGPoint {CGPoint(x:p.x*g.size.width,y:(1-p.y)*g.size.height)}
                                    path.move(to:pt(c.nodes[0].point))
                                    for i in 1..<c.nodes.count {path.addCurve(to:pt(c.nodes[i].point),control1:pt(c.nodes[i-1].outgoing),control2:pt(c.nodes[i].incoming))}
                                }.stroke(Color.mint,lineWidth:2)
                            }.frame(height:45)
                        }.padding(12).background(Color.white.opacity(0.06)).cornerRadius(7)
                    }.buttonStyle(.plain).accessibilityLabel("Añadir curva \(name)")
                }
            }
            HStack {Text("Noise es repetible. Digital y Saw usan saltos muy breves.").font(.caption).foregroundColor(.secondary);Spacer();Button("Añadir todas"){store.addEnvelopePresets(EnvelopePresets.names);onClose()}.disabled(store.envelopeLibrary.count+11>512)}
        }.padding(20).frame(width:700).preferredColorScheme(.dark)
    }
}
func runEnvelopePresetTests()throws {
    for name in EnvelopePresets.names {
        let c=EnvelopePresets.curve(name);precondition(c.valid,"Invalid preset: \(name)")
        let restored=try JSONDecoder().decode(BezierEnvelope.self,from:JSONEncoder().encode(c));precondition(restored==c)
        for i in 0...1024 {let v=c.value(Double(i)/1024);precondition(v.isFinite && (0...1).contains(v))}
    }
    precondition(EnvelopePresets.curve("Noise")==EnvelopePresets.curve("Noise"))
    let d=EnvelopePresets.curve("Digital");precondition(d.value(0.1)>0.99 && d.value(0.3)<0.01 && d.value(0.6)>0.99 && d.value(0.8)<0.01)
    let s=EnvelopePresets.curve("Saw");precondition(s.value(0.249)<0.01 && s.value(0.251)>0.99)
    let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:temp)}
    let store=Store(recoveryStorage:RecoveryStorage(directory:temp),startTimer:false);defer{store.recoveryWork?.cancel()}
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let before=try encoder.encode(store.project)
    store.addEnvelopePresets(EnvelopePresets.names);let after=try encoder.encode(store.project);precondition(store.envelopeLibrary.count==12 && after==before)
    store.addEnvelopePresets(EnvelopePresets.names);precondition(store.envelopeLibrary.count==12)
    store.undoEdit();precondition(store.envelopeLibrary.count==1);store.redoEdit();precondition(store.envelopeLibrary.count==12)
    print("PASS: 11 reference curve presets, bounded samples, digital/saw edges, deterministic noise, roundtrip, additive library, duplicate protection and undo")
}
