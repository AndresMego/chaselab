// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import SwiftUI
import AppKit
import Combine

struct CurvePoint:Codable,Equatable {
    var x:Double;var y:Double
    func mixed(_ other:Self,_ t:Double)->Self { Self(x:x+(other.x-x)*t,y:y+(other.y-y)*t) }
    var valid:Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}
struct CurveNode:Codable,Equatable {
    var point:CurvePoint;var incoming:CurvePoint;var outgoing:CurvePoint
}
struct BezierEnvelope:Codable,Equatable {
    var nodes:[CurveNode]
    static func line(_ start:Double,_ end:Double)->Self {
        let a=CurvePoint(x:0,y:start),b=CurvePoint(x:1,y:end)
        return Self(nodes:[CurveNode(point:a,incoming:a,outgoing:a.mixed(b,1/3)),CurveNode(point:b,incoming:a.mixed(b,2/3),outgoing:b)])
    }
    static func preset(_ name:String)->Self {
        if name=="Corte" { return line(1,1) }
        if name=="Pulso" {
            return Self(nodes:[
                CurveNode(point:CurvePoint(x:0,y:0),incoming:CurvePoint(x:0,y:0),outgoing:CurvePoint(x:0.18,y:0.56)),
                CurveNode(point:CurvePoint(x:0.5,y:1),incoming:CurvePoint(x:0.32,y:1),outgoing:CurvePoint(x:0.68,y:1)),
                CurveNode(point:CurvePoint(x:1,y:0),incoming:CurvePoint(x:0.82,y:0.56),outgoing:CurvePoint(x:1,y:0))])
        }
        return line(1,0)
    }
    var valid:Bool {
        guard (2...64).contains(nodes.count),nodes.first!.point.x==0,nodes.last!.point.x==1,
              nodes.allSatisfy({$0.point.valid && $0.incoming.valid && $0.outgoing.valid}) else { return false }
        for i in 0..<nodes.count-1 {
            let a=nodes[i],b=nodes[i+1]
            if b.point.x-a.point.x<0.0001 || a.outgoing.x<a.point.x || a.outgoing.x>b.incoming.x || b.incoming.x>b.point.x { return false }
        }
        return true
    }
    static func cubic(_ a:Double,_ b:Double,_ c:Double,_ d:Double,_ t:Double)->Double {
        let u=1-t;return u*u*u*a+3*u*u*t*b+3*u*t*t*c+t*t*t*d
    }
    func value(_ phase:Double)->Double {
        guard nodes.count>=2 else { return 0 }
        let x=max(0,min(1,phase.isFinite ? phase:0))
        let i=nodes.indices.dropLast().first(where:{x<=nodes[$0+1].point.x}) ?? nodes.count-2
        let a=nodes[i],b=nodes[i+1]
        var low=0.0,high=1.0
        for _ in 0..<28 {
            let t=(low+high)/2
            if Self.cubic(a.point.x,a.outgoing.x,b.incoming.x,b.point.x,t)<x { low=t } else { high=t }
        }
        return max(0,min(1,Self.cubic(a.point.y,a.outgoing.y,b.incoming.y,b.point.y,(low+high)/2)))
    }
    mutating func constrain() {
        for i in nodes.indices {
            let lower=i==0 ? 0:nodes[i-1].point.x,upper=i==nodes.count-1 ? 1:nodes[i+1].point.x
            nodes[i].incoming.x=max(lower,min(nodes[i].point.x,nodes[i].incoming.x))
            nodes[i].outgoing.x=max(nodes[i].point.x,min(upper,nodes[i].outgoing.x))
            nodes[i].incoming.y=max(0,min(1,nodes[i].incoming.y));nodes[i].outgoing.y=max(0,min(1,nodes[i].outgoing.y))
        }
        for i in 0..<nodes.count-1 where nodes[i].outgoing.x>nodes[i+1].incoming.x {
            let mid=(nodes[i].outgoing.x+nodes[i+1].incoming.x)/2
            nodes[i].outgoing.x=mid;nodes[i+1].incoming.x=mid
        }
    }
    mutating func splitLongest() {
        guard nodes.count<64,let i=(0..<nodes.count-1).max(by:{nodes[$0+1].point.x-nodes[$0].point.x<nodes[$1+1].point.x-nodes[$1].point.x}) else { return }
        let a=nodes[i],b=nodes[i+1]
        let q0=a.point.mixed(a.outgoing,0.5),q1=a.outgoing.mixed(b.incoming,0.5),q2=b.incoming.mixed(b.point,0.5)
        let r0=q0.mixed(q1,0.5),r1=q1.mixed(q2,0.5),center=r0.mixed(r1,0.5)
        nodes[i].outgoing=q0;nodes[i+1].incoming=q2
        nodes.insert(CurveNode(point:center,incoming:r0,outgoing:r1),at:i+1)
    }
}
func level(_ project:Project,_ phase:Double)->Double {
    project.envelope=="Bézier" ? (project.bezier ?? .preset("Fade out")).value(phase):level(project.envelope,phase)
}
extension Store {
    var editableEnvelope:BezierEnvelope {if let i=chosenLibraryIndex {return envelopeLibrary[i].curve};return project.envelope=="Bézier" ? (project.bezier ?? .preset("Fade out")):.preset(project.envelope) }
    var editableShapeName:String {chosenLibraryIndex==nil ? project.envelope:"Bézier"}
    func chooseEnvelope(_ name:String) {
        if chosenLibraryIndex != nil {if name != "Bézier" {setEnvelope(.preset(name))};return}
        guard project.envelope != name else { return }
        recordEdit()
        if name=="Bézier" && project.bezier==nil { project.bezier = .preset(project.envelope) }
        project.libraryEnvelopeID=nil;project.envelope=name
    }
    func setEnvelope(_ curve:BezierEnvelope,record:Bool=true) {
        guard curve.valid else { return }
        if record { recordEdit() }
        if let i=chosenLibraryIndex {
            guard envelopeLibrary[i].curve != curve else {return}
            var entries=envelopeLibrary;entries[i].curve=curve;envelopeLibrary=entries;reconcileLibrarySelection();return
        }
        guard project.bezier != curve || project.envelope != "Bézier" else {return}
        var updated=project;updated.bezier=curve;updated.envelope="Bézier";updated.libraryEnvelopeID=nil;project=updated
    }
}
private struct CurveTarget {var node:Int;var kind:Int}
private final class EnvelopePanelState:ObservableObject {
    @Published var selected:Int?=nil
    @Published var expanded=false
}
struct BezierCanvas:NSViewRepresentable {
    @ObservedObject var store:Store
    @Binding var selected:Int?
    func makeNSView(context:Context)->BezierEditorView { BezierEditorView(store:store) }
    func updateNSView(_ view:BezierEditorView,context:Context) {
        view.selection=selected;view.onSelection={selected=$0};view.needsDisplay=true
    }
}
final class BezierEditorView:NSView {
    let store:Store
    var selection:Int?
    var onSelection:((Int?)->Void)?
    private var target:CurveTarget?
    private var draft:BezierEnvelope?
    private var recorded=false
    private var lastCommit=0.0
    private var playbackSubscription:AnyCancellable?
    init(store:Store) {
        self.store=store;super.init(frame:.zero)
        playbackSubscription=store.playbackUpdates.sink { [weak self] _ in self?.needsDisplay=true }
        setAccessibilityElement(true);setAccessibilityRole(.image);setAccessibilityLabel("Editor de curva Bézier: arrastra puntos y tiradores")
    }
    required init?(coder:NSCoder) {fatalError()}
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.crosshair)}
    private func screen(_ p:CurvePoint)->CGPoint {CGPoint(x:16+p.x*max(1,bounds.width-32),y:16+(1-p.y)*max(1,bounds.height-32))}
    private func handles(_ curve:BezierEnvelope)->[(CurveTarget,CurvePoint)] {
        var result:[(CurveTarget,CurvePoint)]=[]
        for i in curve.nodes.indices {
            result.append((CurveTarget(node:i,kind:0),curve.nodes[i].point))
            if i>0 {result.append((CurveTarget(node:i,kind:1),curve.nodes[i].incoming))}
            if i<curve.nodes.count-1 {result.append((CurveTarget(node:i,kind:2),curve.nodes[i].outgoing))}
        }
        return result
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(calibratedRed:0.035,green:0.045,blue:0.05,alpha:1).setFill();NSBezierPath(roundedRect:bounds,xRadius:6,yRadius:6).fill()
        guard bounds.width>32,bounds.height>32 else {return}
        let curve=draft ?? store.editableEnvelope,w=bounds.width-32,h=bounds.height-32
        let green=NSColor(calibratedRed:0.36,green:0.93,blue:0.77,alpha:1)
        let grid=NSBezierPath()
        for i in 0...4 {let t=Double(i)/4;grid.move(to:CGPoint(x:16+t*w,y:16));grid.line(to:CGPoint(x:16+t*w,y:16+h));grid.move(to:CGPoint(x:16,y:16+t*h));grid.line(to:CGPoint(x:16+w,y:16+t*h))}
        NSColor.white.withAlphaComponent(0.1).setStroke();grid.lineWidth=1;grid.stroke()
        let path=NSBezierPath();path.move(to:screen(curve.nodes[0].point))
        for i in 1..<curve.nodes.count {path.curve(to:screen(curve.nodes[i].point),controlPoint1:screen(curve.nodes[i-1].outgoing),controlPoint2:screen(curve.nodes[i].incoming))}
        green.setStroke();path.lineWidth=2.5;path.stroke()
        green.withAlphaComponent(0.55).setStroke()
        for i in curve.nodes.indices {
            let n=curve.nodes[i],arms=NSBezierPath()
            if i>0 {arms.move(to:screen(n.point));arms.line(to:screen(n.incoming))}
            if i<curve.nodes.count-1 {arms.move(to:screen(n.point));arms.line(to:screen(n.outgoing))}
            arms.lineWidth=1;arms.setLineDash([3,3],count:2,phase:0);arms.stroke()
        }
        for (handle,p) in handles(curve).sorted(by:{$0.0.kind>$1.0.kind}) {
            let c=screen(p),r=handle.kind==0 ? 5.5:4.0
            let circle=NSBezierPath(ovalIn:NSRect(x:c.x-r,y:c.y-r,width:r*2,height:r*2))
            let fill=handle.kind==0 ? (selection==handle.node ? NSColor.white:green):NSColor(calibratedRed:0.08,green:0.13,blue:0.16,alpha:1)
            fill.setFill();circle.fill();green.setStroke();circle.lineWidth=1.5;circle.stroke()
        }
        if store.playing {
            let x=16+store.phase*w,playhead=NSBezierPath();playhead.move(to:CGPoint(x:x,y:16));playhead.line(to:CGPoint(x:x,y:16+h))
            NSColor.orange.withAlphaComponent(0.8).setStroke();playhead.lineWidth=1;playhead.stroke()
        }
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        let location=convert(event.locationInWindow,from:nil),curve=store.editableEnvelope
        let choices=handles(curve).map {handle,p in (handle,hypot(screen(p).x-location.x,screen(p).y-location.y))}.sorted{$0.1<$1.1}
        target=choices.first.flatMap{$0.1<13 ? $0.0:nil};draft=target==nil ? nil:curve;recorded=false;lastCommit=0
        selection=target?.node;onSelection?(selection);needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard let target,var curve=draft,curve.nodes.indices.contains(target.node) else {return}
        let position=convert(event.locationInWindow,from:nil)
        var point=CurvePoint(x:max(0,min(1,(position.x-16)/max(1,bounds.width-32))),y:max(0,min(1,1-(position.y-16)/max(1,bounds.height-32))))
        let i=target.node
        if target.kind==0 {
            if i==0 {point.x=0} else if i==curve.nodes.count-1 {point.x=1}
            else {point.x=max(curve.nodes[i-1].point.x+0.0002,min(curve.nodes[i+1].point.x-0.0002,point.x))}
            let old=curve.nodes[i].point,dx=point.x-old.x,dy=point.y-old.y
            curve.nodes[i].point=point;curve.nodes[i].incoming.x+=dx;curve.nodes[i].incoming.y+=dy
            curve.nodes[i].outgoing.x+=dx;curve.nodes[i].outgoing.y+=dy
        } else if target.kind==1 {curve.nodes[i].incoming=point} else {curve.nodes[i].outgoing=point}
        curve.constrain();guard curve != draft else {return}
        if !recorded {store.recordEdit();recorded=true}
        draft=curve;needsDisplay=true
        let now=ProcessInfo.processInfo.systemUptime
        // Draw every pointer event locally; publish at most 30 times/sec to the rest of the editor.
        if now-lastCommit>=1/30 {store.setEnvelope(curve,record:false);lastCommit=now}
    }
    override func mouseUp(with event:NSEvent) {
        if recorded,let draft {store.setEnvelope(draft,record:false)}
        draft=nil;target=nil;recorded=false;needsDisplay=true
    }
}
struct EnvelopePanel:View {
    @ObservedObject var store:Store
    @StateObject private var ui=EnvelopePanelState()
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            EnvelopeLibraryPanel(store:store)
            Divider()
            Text("INTENSIDAD POR PASO").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Picker("Forma",selection:Binding(get:{store.editableShapeName},set:store.chooseEnvelope)) {
                ForEach(["Corte","Fade out","Pulso","Bézier"],id:\.self){Text($0)}
            }
            BezierCanvas(store:store,selected:$ui.selected).frame(height:180)
            HStack {Text("0% tiempo");Spacer();Text("100%")}.font(.system(size:9)).foregroundColor(.secondary)
            Button("Ampliar editor…"){ui.expanded=true}
            HStack {
                Button("+ Punto"){var c=store.editableEnvelope;c.splitLongest();store.setEnvelope(c);ui.selected=nil}.disabled(store.editableEnvelope.nodes.count>=64)
                Button("− Punto"){
                    if let i=ui.selected,i>0,i<store.editableEnvelope.nodes.count-1 {var c=store.editableEnvelope;c.nodes.remove(at:i);c.constrain();store.setEnvelope(c);ui.selected=nil}
                }.disabled(ui.selected==nil || ui.selected==0 || ui.selected!>=store.editableEnvelope.nodes.count-1)
            }
            Text("Arrastra los puntos para mover la curva y los tiradores para cambiar su curvatura. Cada arrastre se puede deshacer.").font(.caption).foregroundColor(.secondary)
            Text("La curva se adapta a cada paso. Si eliges una envolvente de biblioteca, editarla actualiza esa curva compartida. Arena puede elegir otra por instancia.").font(.caption).foregroundColor(.secondary)
            HStack {Button("Deshacer",action:store.undoEdit).disabled(store.undoStates.isEmpty);Button("Rehacer",action:store.redoEdit).disabled(store.redoStates.isEmpty)}
        }.sheet(isPresented:$ui.expanded) {
            VStack(alignment:.leading,spacing:14) {
                HStack {Text("Envolvente Bézier").font(.title2);Spacer();Button("Listo"){ui.expanded=false}.keyboardShortcut(.cancelAction)}
                Text("Arriba: 100% intensidad · Abajo: 0% · Izquierda: inicio del paso · Derecha: final").font(.caption).foregroundColor(.secondary)
                BezierCanvas(store:store,selected:$ui.selected).frame(minWidth:600,minHeight:340)
                HStack {Button("Deshacer",action:store.undoEdit).disabled(store.undoStates.isEmpty);Button("Rehacer",action:store.redoEdit).disabled(store.redoStates.isEmpty);Spacer();Text("Se aplica y guarda automáticamente").font(.caption).foregroundColor(.secondary)}
            }.padding(20).frame(width:680,height:470).preferredColorScheme(.dark)
        }
    }
}
