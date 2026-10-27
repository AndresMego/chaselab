// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import SwiftUI
import AppKit
import Combine

struct CanvasTransform {
    var view:CGSize;var project:CGSize;var zoom:Double;var pan:CGSize
    var scale:Double { min((view.width-32)/project.width,(view.height-32)/project.height)*zoom }
    var origin:CGPoint { CGPoint(x:(view.width-project.width*scale)/2+pan.width,y:(view.height-project.height*scale)/2+pan.height) }
    func screen(_ p:Point)->CGPoint { CGPoint(x:origin.x+p.x*scale,y:origin.y+p.y*scale) }
    func zoomed(to value:Double,around point:CGPoint)->CGSize {
        let ratio=value/zoom
        return CGSize(width:point.x-view.width/2-(point.x-view.width/2-pan.width)*ratio,height:point.y-view.height/2-(point.y-view.height/2-pan.height)*ratio)
    }
}

final class PreviewViewport:ObservableObject {
    @Published var zoom=1.0
    @Published var pan=CGSize.zero
    @Published var tool="Editar"
    @Published var hover=""
    func fit() { zoom=1;pan = .zero }
}

struct PreviewCanvas:NSViewRepresentable {
    @ObservedObject var store:Store
    @ObservedObject var viewport:PreviewViewport
    var names:Bool
    var factoryMode=false
    func makeNSView(context:Context)->CanvasEditorView { CanvasEditorView(store:store,viewport:viewport) }
    func updateNSView(_ view:CanvasEditorView,context:Context) {
        view.names=names
        if view.factoryMode != factoryMode {
            // Cancel guide editing when the overlay is hidden; hidden lines cannot intercept painting or Delete.
            view.gridDragging=false;view.gridRecorded=false;view.selectedBorder=nil
        }
        view.factoryMode=factoryMode;view.needsDisplay=true;view.window?.invalidateCursorRects(for:view)
    }
}

final class CanvasEditorView:NSView {
    let store:Store;let viewport:PreviewViewport
    var names=false
    var middlePanning=false
    var middleStart=CGPoint.zero,middlePanStart=CGSize.zero
    var factoryMode=false
    var selectedBorder:(axis:Int,index:Int)?
    var gridDragging=false,gridRecorded=false,duplicateBorder=false
    var hoverRow:Int?
    var dragStart=CGPoint.zero,panStart=CGSize.zero,lastPoint=CGPoint.zero
    var drawing=false,strokeRecorded=false,paintValue=false
    var visited=Set<Int>()
    var tracking:NSTrackingArea?
    var playbackSubscription:AnyCancellable?
    init(store:Store,viewport:PreviewViewport) {
        self.store=store;self.viewport=viewport
        super.init(frame:.zero)
        playbackSubscription=store.playbackUpdates.sink { [weak self] _ in self?.needsDisplay=true }
        setAccessibilityElement(true);setAccessibilityRole(.image);setAccessibilityLabel("Lienzo de slices · zoom y mano")
    }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    var transform:CanvasTransform { CanvasTransform(view:bounds.size,project:CGSize(width:store.project.width,height:store.project.height),zoom:viewport.zoom,pan:viewport.pan) }
    func path(_ slice:Slice)->NSBezierPath {
        let result=NSBezierPath();let t=transform
        if let p=slice.points.first { result.move(to:t.screen(p));for p in slice.points.dropFirst() { result.line(to:t.screen(p)) };result.close() }
        return result
    }
    func hit(_ point:CGPoint)->Int? { store.project.slices.indices.reversed().first { path(store.project.slices[$0]).contains(point) } }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking=NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseMoved,.mouseEnteredAndExited,.inVisibleRect],owner:self)
        addTrackingArea(tracking!);super.updateTrackingAreas()
    }
    override func resetCursorRects() { addCursorRect(bounds,cursor:middlePanning ? .closedHand:(viewport.tool=="Mano" ? .openHand:.crosshair)) }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(calibratedRed:0.035,green:0.045,blue:0.06,alpha:1).setFill();bounds.fill()
        guard bounds.width>32,bounds.height>32 else { return }
        let t=transform,p=store.project
        let canvas=NSRect(origin:t.origin,size:CGSize(width:p.width*t.scale,height:p.height*t.scale))
        NSColor.black.setFill();canvas.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke();NSBezierPath(rect:canvas).stroke()
        let green=NSColor(calibratedRed:0.3,green:0.9,blue:0.72,alpha:1)
        for (r,slice) in p.slices.enumerated() {
            let shape=path(slice),active=p.sequences[store.selected].cells[r][store.playing ? store.step:store.editStep]
            (active ? green.withAlphaComponent(store.playing ? level(p,store.phase):0.85):NSColor.white.withAlphaComponent(0.045)).setFill();shape.fill()
            (hoverRow==r ? NSColor.orange:active ? green:NSColor.white.withAlphaComponent(0.32)).setStroke()
            shape.lineWidth=hoverRow==r ? 2:1;shape.stroke()
        }
        // Names that cannot fit a narrow slice are shown on hover, never stacked on top of each other.
        var occupied:[NSRect]=[]
        if names {
            for (r,slice) in p.slices.enumerated() where r != hoverRow {
                let box=path(slice).bounds
                let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:10,weight:.medium),.foregroundColor:NSColor.white]
                let text=slice.name as NSString;let size=text.size(withAttributes:attrs)
                let label=NSRect(x:box.midX-size.width/2-3,y:box.midY-8,width:size.width+6,height:16)
                if box.width>=label.width+4 && box.height>=20 && bounds.contains(label) && !occupied.contains(where:{$0.intersects(label.insetBy(dx:-3,dy:-3))}) {
                    NSColor.black.withAlphaComponent(0.8).setFill();label.fill();text.draw(at:CGPoint(x:label.minX+3,y:label.minY+1),withAttributes:attrs);occupied.append(label)
                }
            }
        }
        if let r=hoverRow,p.slices.indices.contains(r) {
            let text=p.slices[r].name as NSString,box=path(p.slices[r]).bounds
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:NSColor.white]
            let size=text.size(withAttributes:attrs)
            let label=NSRect(x:max(4,min(bounds.width-size.width-12,box.midX-size.width/2-5)),y:max(4,min(bounds.height-24,box.minY-24)),width:size.width+10,height:20)
            NSColor.black.withAlphaComponent(0.9).setFill();NSBezierPath(roundedRect:label,xRadius:3,yRadius:3).fill();text.draw(at:CGPoint(x:label.minX+5,y:label.minY+3),withAttributes:attrs)
        }
        if factoryMode {
            let settings=store.factory
            for axis in 0...1 {
                for (index,value) in (axis==0 ? settings.x:settings.y).enumerated() {
                    let line=NSBezierPath()
                    if axis==0 { let x=t.origin.x+value*t.scale;line.move(to:CGPoint(x:x,y:canvas.minY));line.line(to:CGPoint(x:x,y:canvas.maxY)) }
                    else { let y=t.origin.y+value*t.scale;line.move(to:CGPoint(x:canvas.minX,y:y));line.line(to:CGPoint(x:canvas.maxX,y:y)) }
                    let selected=selectedBorder?.axis==axis && selectedBorder?.index==index
                    (selected ? NSColor.orange:NSColor.systemCyan.withAlphaComponent(0.8)).setStroke()
                    line.lineWidth=selected ? 2:1;line.setLineDash([5,4],count:2,phase:0);line.stroke()
                }
            }
        }
    }
    override func mouseMoved(with event:NSEvent) {
        hoverRow=hit(convert(event.locationInWindow,from:nil))
        viewport.hover=hoverRow.map{store.project.slices[$0].name} ?? "";needsDisplay=true
    }
    override func mouseExited(with event:NSEvent) { hoverRow=nil;viewport.hover="";needsDisplay=true }
    override func mouseDown(with event:NSEvent) {
        guard !middlePanning else { return }
        window?.makeFirstResponder(self)
        dragStart=convert(event.locationInWindow,from:nil);lastPoint=dragStart;panStart=viewport.pan
        if factoryMode && viewport.tool=="Editar" {
            let t=transform,f=store.factory
            var nearest:(axis:Int,index:Int,distance:Double)?
            for axis in 0...1 {
                for (i,value) in (axis==0 ? f.x:f.y).enumerated() {
                    let distance=abs((axis==0 ? dragStart.x-t.origin.x:dragStart.y-t.origin.y)-value*t.scale)
                    if distance<7 && (nearest == nil || distance<nearest!.distance) { nearest=(axis,i,distance) }
                }
            }
            selectedBorder=nearest.map{($0.axis,$0.index)}
            gridDragging=selectedBorder != nil;gridRecorded=false;duplicateBorder=event.modifierFlags.contains(.option)
            drawing=false;needsDisplay=true;return
        }
        drawing=viewport.tool=="Editar";strokeRecorded=false;visited=[]
        if drawing { paint(at:dragStart) } else { NSCursor.closedHand.set() }
    }
    func paint(at point:CGPoint) {
        guard let row=hit(point),!visited.contains(row) else { return }
        if !strokeRecorded { store.recordEdit();paintValue = !store.project.sequences[store.selected].cells[row][store.editStep];strokeRecorded=true }
        visited.insert(row);store.project.sequences[store.selected].cells[row][store.editStep]=paintValue;needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard !middlePanning else { return }
        let point=convert(event.locationInWindow,from:nil)
        if factoryMode && viewport.tool=="Editar" {
            guard gridDragging,let selected=selectedBorder else { return }
            var f=store.factory
            var values=selected.axis==0 ? f.x:f.y
            guard values.indices.contains(selected.index) else { return }
            if !gridRecorded { store.recordEdit();gridRecorded=true }
            let t=transform
            let limit=selected.axis==0 ? store.project.width:store.project.height
            let value=max(0.001,min(limit-0.001,((selected.axis==0 ? point.x-t.origin.x:point.y-t.origin.y)/t.scale)))
            if duplicateBorder && values.count<255 { values.append(value);duplicateBorder=false }
            else { values[selected.index]=value }
            values.sort()
            // Keep borders strictly ordered while dragging across another border.
            var unique:[Double]=[]
            for v in values { if unique.last.map({abs($0-v)>0.0001}) ?? true { unique.append(v) } }
            if selected.axis==0 { f.x=unique } else { f.y=unique }
            selectedBorder=(selected.axis,unique.indices.min(by:{abs(unique[$0]-value)<abs(unique[$1]-value)}) ?? 0)
            store.updateFactory(f,record:false);needsDisplay=true;return
        }
        if drawing {
            let distance=hypot(point.x-lastPoint.x,point.y-lastPoint.y)
            let samples=max(1,Int(ceil(distance/2)))
            for i in 1...samples {
                let fraction=Double(i)/Double(samples)
                paint(at:CGPoint(x:lastPoint.x+(point.x-lastPoint.x)*fraction,y:lastPoint.y+(point.y-lastPoint.y)*fraction))
            }
            lastPoint=point
        }
        else { viewport.pan=CGSize(width:panStart.width+point.x-dragStart.x,height:panStart.height+point.y-dragStart.y);needsDisplay=true }
    }
    override func mouseUp(with event:NSEvent) { drawing=false;strokeRecorded=false;gridDragging=false;gridRecorded=false;visited=[];window?.invalidateCursorRects(for:self) }
    // Middle-button pan is a temporary view gesture; it never edits the project or selected tool.
    override func otherMouseDown(with event:NSEvent) {
        guard event.buttonNumber==2 else { super.otherMouseDown(with:event);return }
        guard !drawing && !gridDragging else { return }
        window?.makeFirstResponder(self)
        middlePanning=true;middleStart=convert(event.locationInWindow,from:nil);middlePanStart=viewport.pan
        hoverRow=nil;viewport.hover="";window?.invalidateCursorRects(for:self);NSCursor.closedHand.set();needsDisplay=true
    }
    override func otherMouseDragged(with event:NSEvent) {
        guard event.buttonNumber==2 && middlePanning else { super.otherMouseDragged(with:event);return }
        let point=convert(event.locationInWindow,from:nil)
        viewport.pan=CGSize(width:middlePanStart.width+point.x-middleStart.x,height:middlePanStart.height+point.y-middleStart.y)
        NSCursor.closedHand.set();needsDisplay=true
    }
    override func otherMouseUp(with event:NSEvent) {
        guard event.buttonNumber==2 && middlePanning else { super.otherMouseUp(with:event);return }
        middlePanning=false;window?.invalidateCursorRects(for:self)
        (viewport.tool=="Mano" ? NSCursor.openHand:NSCursor.crosshair).set();needsDisplay=true
    }
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        if window?.firstResponder === self,event.modifierFlags.contains(.command),event.charactersIgnoringModifiers?.lowercased()=="z" {
            if event.modifierFlags.contains(.shift) { store.redoEdit() } else { store.undoEdit() };needsDisplay=true;return true
        }
        return super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event:NSEvent) {
        if factoryMode,let selected=selectedBorder,[51,117].contains(event.keyCode) {
            var f=store.factory
            if selected.axis==0,f.x.indices.contains(selected.index) { f.x.remove(at:selected.index) }
            else if selected.axis==1,f.y.indices.contains(selected.index) { f.y.remove(at:selected.index) }
            store.updateFactory(f);selectedBorder=nil;needsDisplay=true;return
        }
        super.keyDown(with:event)
    }
    func zoom(to value:Double,around point:CGPoint) {
        let limited=max(0.25,min(8,value));viewport.pan=transform.zoomed(to:limited,around:point);viewport.zoom=limited;needsDisplay=true
    }
    override func scrollWheel(with event:NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) { zoom(to:viewport.zoom*exp(event.scrollingDeltaY*0.015),around:convert(event.locationInWindow,from:nil)) }
        else { viewport.pan=CGSize(width:viewport.pan.width+event.scrollingDeltaX,height:viewport.pan.height+event.scrollingDeltaY);needsDisplay=true }
    }
    override func magnify(with event:NSEvent) { zoom(to:viewport.zoom*(1+event.magnification),around:convert(event.locationInWindow,from:nil)) }
}
