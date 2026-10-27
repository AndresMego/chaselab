// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import SwiftUI
import AppKit
import Foundation
import AVFoundation
import Combine

struct Point: Codable { var x: Double; var y: Double }
struct Slice: Codable, Identifiable { var id = UUID(); var name: String; var points: [Point]; var sourceID:String? = nil }
struct Sequence: Codable, Identifiable { var id = UUID(); var name: String; var cells: [[Bool]]; var durations:[Double]? = nil; var factory:FactorySettings? = nil }
struct Project: Codable {
    var version = 5
    var width = 1920.0; var height = 1080.0
    var bpm = 120.0; var division = 2.0; var envelope = "Corte"
    var bezier:BezierEnvelope? = nil
    var arenaPreset:String? = nil
    var libraryEnvelopeID:String? = nil
    var slices: [Slice]; var sequences: [Sequence]
}
func demoProject() -> Project {
    let slices = (0..<8).map { i in
        let x = Double(i % 4) * 480 + 24, y = Double(i / 4) * 540 + 24
        return Slice(name: "Slice \(i+1)", points: [Point(x:x,y:y),Point(x:x+432,y:y),Point(x:x+432,y:y+492),Point(x:x,y:y+492)])
    }
    let cells = (0..<8).map { r in (0..<16).map { $0 % 8 == r } }
    return Project(slices:slices, sequences:[Sequence(name:"Chase 01", cells:cells)])
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
func loadSlices(_ url: URL) throws -> (Double, Double, [Slice]) {
    guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 20_000_000 else { throw AppError.message("El XML supera 20 MB.") }
    let xml=try XMLDocument(contentsOf:url,options:[.nodeLoadExternalEntitiesNever])
    let size=try xml.nodes(forXPath:"//CurrentCompositionTextureSize").first as? XMLElement
    guard let w=Double(size?.attribute(forName:"width")?.stringValue ?? "1920"),let h=Double(size?.attribute(forName:"height")?.stringValue ?? "1080"),w.isFinite,h.isFinite,w>0,h>0,w<=16384,h<=16384 else { throw AppError.message("La resolución del XML no es válida; máximo 16 384 píxeles por lado.") }
    let nodes=try xml.nodes(forXPath:"//Slice")
    guard !nodes.isEmpty,nodes.count<=256 else { throw AppError.message("El XML debe contener entre 1 y 256 slices.") }
    var slices:[Slice]=[]
    for (index,node) in nodes.enumerated() {
        guard let e=node as? XMLElement else { throw AppError.message("Slice \(index+1) no válido.") }
        let name=try e.nodes(forXPath:"./Params[@name='Common']/Param[@name='Name']/@value").first?.stringValue ?? "Slice \(index+1)"
        let vertices=try e.nodes(forXPath:"./InputRect/v")
        guard (3...1024).contains(vertices.count) else { throw AppError.message("\(name): faltan puntos de entrada o supera 1024 vértices. No se importó ningún slice.") }
        var points:[Point]=[]
        for vertex in vertices {
            guard let v=vertex as? XMLElement,let x=Double(v.attribute(forName:"x")?.stringValue ?? ""),let y=Double(v.attribute(forName:"y")?.stringValue ?? ""),x.isFinite,y.isFinite,abs(x)<1e7,abs(y)<1e7 else { throw AppError.message("\(name): contiene coordenadas inválidas. No se importó ningún slice.") }
            points.append(Point(x:x,y:y))
        }
        let screen=try e.nodes(forXPath:"ancestor::Screen/@uniqueId").first?.stringValue ?? "screen"
        let source=e.attribute(forName:"uniqueId")?.stringValue
        slices.append(Slice(name:name,points:points,sourceID:source.map{screen+":"+$0}))
    }
    return (w,h,slices)
}
func level(_ envelope: String, _ phase: Double) -> Double {
    switch envelope { case "Fade out": return 1-phase; case "Pulso": return sin(phase * .pi); default: return 1 }
}
func validate(_ p: Project) -> Bool {
    [1,2,3,4,5].contains(p.version) && p.width.isFinite && p.height.isFinite && p.width > 0 && p.height > 0 && p.width <= 16384 && p.height <= 16384 && p.bpm.isFinite && (20...300).contains(p.bpm) && [1.0,2.0,4.0].contains(p.division) && ["Corte","Fade out","Pulso","Bézier"].contains(p.envelope) && (p.bezier == nil || p.bezier!.valid) && (p.envelope != "Bézier" || p.bezier != nil) && !p.slices.isEmpty && p.slices.count <= 256 && Set(p.slices.map(\.id)).count == p.slices.count && p.slices.allSatisfy { $0.points.count >= 3 && $0.points.count <= 1024 && $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1e7 && abs($0.y) < 1e7 } } && !p.sequences.isEmpty && p.sequences.count <= 128 && Set(p.sequences.map(\.id)).count == p.sequences.count && p.sequences.allSatisfy { s in (s.factory == nil || s.factory!.valid) && s.cells.count == p.slices.count && (1...256).contains(s.cells.first?.count ?? 0) && s.cells.allSatisfy { $0.count == s.cells.first?.count } && (s.durations == nil || (s.durations!.count == s.cells.first?.count && s.durations!.allSatisfy { $0.isFinite && SequenceTiming.choices.contains($0) })) }
}
class Store: ObservableObject {
    @Published var project = demoProject() { didSet { catalogRevision &+= 1;scheduleRecovery() } }
    var catalogRevision:UInt64=0
    var publishedCatalogRevision:UInt64?
    @Published var arenaResolutionStatus="Player: sin comprobación de resolución"
    @Published var selected = 0 { didSet { scheduleRecovery() } }; @Published var step = 0
    @Published var editStep=0 { didSet { scheduleRecovery() } }
    struct CopiedStep { var slices:[UUID];var values:[Bool];var duration:Double }
    @Published var copiedStep:CopiedStep?
    var paintSequence:UUID?;var paintValue=false;var paintPrevious:GridCell?
    @Published var playing = false; var phase = 0.0
    let playbackUpdates=PassthroughSubject<Void,Never>()
    @Published var status = "Proyecto de ejemplo · 8 slices"
    @Published var exporting = false
    @Published var liveEnabled = false
    @Published var liveStatus = "Arena desconectado"
    @Published var followArenaBpm = false { didSet { scheduleRecovery() } }
    @Published var followArenaPhase=false { didSet { arenaClock.reset();scheduleRecovery() } }
    var arenaClock=ArenaClock()
    @Published var arenaPhaseStatus="Fase libre"
    @Published var arenaTempoStatus = "BPM de Arena sin señal"
    @Published var recoveryStatus = "Recuperación automática activada"
    struct EditState { var project:Project;var selected:Int;var step:Int;var editStep:Int;var envelopes:[NamedEnvelope]?=nil;var librarySelection:String?=nil }
    @Published var undoStates:[EditState]=[]
    @Published var redoStates:[EditState]=[]
    @Published var selectedLibraryEnvelopeID:String?
    let envelopeStorage:EnvelopeLibraryStorage
    @Published var envelopeLibrary:[NamedEnvelope]=[] {didSet {catalogRevision &+= 1;scheduleRecovery()}}
    let recovery:RecoveryStorage
    var recoveryWork:DispatchWorkItem?
    var recovering = false
    let bridge:LiveBridge
    let arenaOutput=ArenaOutputSync()
    @Published var syncOutput=false
    @Published var outputSyncStatus="Montaje sin vincular"
    var bridgeTick = 0
    var anchor = ProcessInfo.processInfo.systemUptime
    var timer: Timer?; var output: NSWindow?
    var count: Int { project.sequences[selected].cells.first?.count ?? 16 }
    var timing:SequenceTiming { SequenceTiming(project.sequences[selected]) }
    var canPasteStep:Bool { copiedStep?.slices == project.slices.map(\.id) }
    var duration: Double { 60 / min(300,max(20,project.bpm.isFinite ? project.bpm : 120)) / project.division }
    init(recoveryStorage:RecoveryStorage=RecoveryStorage(),startTimer:Bool=true,liveBridge:LiveBridge=LiveBridge()) {
        recovery=recoveryStorage;bridge=liveBridge
        envelopeStorage=EnvelopeLibraryStorage(directory:recoveryStorage.legacyDirectory != nil ? nil:recoveryStorage.directory.appendingPathComponent("EnvelopeLibrary"))
        recovering=true
        envelopeLibrary=envelopeStorage.load()
        if let saved=recovery.load() {
            project=saved.project;project.version=5;selected=saved.selected;step=saved.step;editStep=saved.editStep ?? saved.step;followArenaBpm=saved.followArenaBpm;followArenaPhase=saved.followArenaPhase ?? false
            status="Proyecto recuperado · reproducción en pausa"
        }
        reconcileLibrarySelection()
        recovering=false
        guard startTimer else { return }
        let t=Timer(timeInterval:1/60,repeats:true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t,forMode:.common)
        RunLoop.main.add(t,forMode:RunLoop.Mode("NSModalPanelRunLoopMode"))
        timer=t
    }
    func snapshot()->SessionSnapshot { SessionSnapshot(project:project,selected:selected,step:step,followArenaBpm:followArenaBpm,savedAt:Date(),followArenaPhase:followArenaPhase,editStep:editStep) }
    func scheduleRecovery() {
        guard !recovering else { return }
        recoveryWork?.cancel()
        let work=DispatchWorkItem { [weak self] in self?.saveRecovery() }
        recoveryWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.8,execute:work)
    }
    @discardableResult func saveRecovery()->Bool {
        guard validate(project) else { recoveryStatus="Proyecto inválido: revisa el tempo antes de cerrar";return false }
        do { try envelopeStorage.save(envelopeLibrary);try recovery.save(snapshot());recoveryStatus="Recuperación al día";return true }
        catch { recoveryStatus="No se pudo guardar recuperación: \(error.localizedDescription)";return false }
    }
    func preserveBeforeReplace() throws { try recovery.preserve(snapshot());saveRecovery() }
    func tick() {
        bridgeTick += 1
        if liveEnabled && bridgeTick % 60 == 0 {
            let next=bridge.playerStatus()
            if arenaResolutionStatus != next { arenaResolutionStatus=next }
        }
        if liveEnabled && bridgeTick % 6 == 0 && publishedCatalogRevision != catalogRevision {
            if bridge.publishCatalog(project:project,revision:catalogRevision,envelopes:envelopeLibrary,completion:{ error in
                if let error { self.publishedCatalogRevision=nil;self.status="No se pudo enviar el proyecto a Player: \(error)" }
            }) { publishedCatalogRevision=catalogRevision }
        }
        if syncOutput && bridgeTick % 120 == 0 { arenaOutput.check(store:self) }
        if liveEnabled && bridgeTick % 3 == 0 {
            let feedback=bridge.feedback()
            let nextLiveStatus=feedback == nil ? "Esperando complemento en Arena…" : "Receptor FFGL activo"
            if liveStatus != nextLiveStatus { liveStatus=nextLiveStatus }
            if let bpm=feedback?.bpm {
                let nextTempoStatus=String(format:"Arena · %.2f BPM",bpm)
                if arenaTempoStatus != nextTempoStatus { arenaTempoStatus=nextTempoStatus }
                if followArenaBpm && abs(project.bpm-bpm)>0.001 { project.bpm=bpm;tempoChanged() }
                if let bar=feedback?.barPhase,let time=feedback?.beatTime {
                    arenaClock.receive(bpm:bpm,barPhase:bar,time:time,now:Date().timeIntervalSince1970)
                }
            } else if arenaTempoStatus != "BPM de Arena sin señal" { arenaTempoStatus="BPM de Arena sin señal" }
        }
        let locked=followArenaBpm && followArenaPhase && liveEnabled ? arenaClock.position(at:Date().timeIntervalSince1970,division:project.division,count:count,cycleLength:timing.total):nil
        let nextPhaseStatus=followArenaBpm && followArenaPhase ? (locked == nil ? "Sin fase · continúa reloj local":"Compás sincronizado · 4 tiempos"):"Fase libre"
        if arenaPhaseStatus != nextPhaseStatus { arenaPhaseStatus=nextPhaseStatus }
        if playing {
            let pos=locked ?? max(0,(ProcessInfo.processInfo.systemUptime-anchor)/duration)
            let location=timing.location(pos)
            if step != location.step { step=location.step };phase=location.phase
            playbackUpdates.send()
            // Preserve the last host position for a smooth fallback after signal loss.
            if locked != nil { anchor=ProcessInfo.processInfo.systemUptime-pos*duration }
        }
        if liveEnabled && bridgeTick % 2 == 0 {
            bridge.send(project:project,selected:selected,step:step,phase:phase,playing:playing,enabled:true) { error in
                if let error { self.liveEnabled=false;self.liveStatus="Error de conexión: \(error)" }
            }
        }
    }
    func toggleLive() {
        if liveEnabled {
            liveEnabled=false;liveStatus="Arena desconectado";arenaClock.reset();arenaTempoStatus="BPM de Arena sin señal"
            bridge.send(project:project,selected:selected,step:step,phase:phase,playing:playing,enabled:false) { _ in }
        } else {
            do { try bridge.prepare();publishedCatalogRevision=nil;arenaClock.reset();liveEnabled=true;liveStatus="Esperando complemento en Arena…" }
            catch { fail(error) }
        }
    }
    func play() { if playing { playing = false; phase = 0 } else { anchor = ProcessInfo.processInfo.systemUptime - timing.offset(step)*duration; playing = true } }
    func seek(_ n: Int) { step = n % count; phase = 0; anchor = ProcessInfo.processInfo.systemUptime - timing.offset(step)*duration }
    func select(_ n: Int) { endPaint();selected = n;editStep=0;seek(0) }
    func selectEditStep(_ n:Int) { guard (0..<count).contains(n) else { return };editStep=n;if !playing { seek(n) } }
    func alignBar() { arenaClock.reset();seek(0) }
    func tempoChanged() { anchor = ProcessInfo.processInfo.systemUptime - (timing.offset(step)+phase*timing.weights[step])*duration }
    func editState()->EditState { EditState(project:project,selected:selected,step:step,editStep:editStep,envelopes:envelopeLibrary,librarySelection:selectedLibraryEnvelopeID) }
    func recordEdit() {
        endPaint()
        undoStates.append(editState());if undoStates.count>40 { undoStates.removeFirst() };redoStates=[]
    }
    func restoreEdit(_ state:EditState) {
        recovering=true;selected=0;project=state.project;if let entries=state.envelopes {envelopeLibrary=entries};selectedLibraryEnvelopeID=state.librarySelection;selected=state.selected;seek(state.step);editStep=min(state.editStep,count-1);recovering=false;scheduleRecovery()
    }
    func undoEdit() { endPaint();guard let state=undoStates.popLast() else { return };redoStates.append(editState());restoreEdit(state) }
    func redoEdit() { endPaint();guard let state=redoStates.popLast() else { return };undoStates.append(editState());restoreEdit(state) }
    func toggle(_ r: Int, _ c: Int) { recordEdit();selectEditStep(c);project.sequences[selected].cells[r][c].toggle() }
    func endPaint() { paintSequence=nil;paintPrevious=nil }
    func paint(x:Double,y:Double) {
        guard let cell=GridLayout.cell(x:x,y:y,rows:project.slices.count,columns:count) else {
            if x<124 || y<0 || x>=124+Double(count)*34 || y>=Double(project.slices.count)*29 { paintPrevious=nil }
            return
        }
        paint(cell)
    }
    func paint(_ cell:GridCell) {
        guard project.slices.indices.contains(cell.row),(0..<count).contains(cell.column) else { return }
        if paintSequence == nil {
            recordEdit();paintSequence=project.sequences[selected].id;paintValue = !project.sequences[selected].cells[cell.row][cell.column];selectEditStep(cell.column)
        }
        guard paintSequence == project.sequences[selected].id else { return }
        let line=GridLayout.line(from:paintPrevious ?? cell,to:cell)
        var cells=project.sequences[selected].cells;var changed=false
        for c in line where cells[c.row][c.column] != paintValue { cells[c.row][c.column]=paintValue;changed=true }
        if changed { project.sequences[selected].cells=cells }
        paintPrevious=cell
    }
    func copyStep() {
        copiedStep=CopiedStep(slices:project.slices.map(\.id),values:project.sequences[selected].cells.map { $0[editStep] },duration:timing.weights[editStep])
        status="Paso \(editStep+1) copiado · incluye su duración"
    }
    func pasteStep() {
        guard canPasteStep,let copied=copiedStep else { return };recordEdit()
        var seq=project.sequences[selected]
        for r in seq.cells.indices { seq.cells[r][editStep]=copied.values[r] }
        var weights=timing.weights;weights[editStep]=copied.duration;seq.durations=weights;project.sequences[selected]=seq;tempoChanged()
        status="Paso pegado en \(editStep+1)"
    }
    func setStepDuration(_ value:Double) {
        guard SequenceTiming.choices.contains(value),value != timing.weights[editStep] else { return };recordEdit()
        var weights=timing.weights;weights[editStep]=value;project.sequences[selected].durations=weights;tempoChanged()
    }
    func moveSequence(_ direction:Int) {
        let target=selected+direction;guard project.sequences.indices.contains(target) else { return }
        recordEdit();project.sequences.swapAt(selected,target);selected=target
    }
    func deleteSequence() {
        guard project.sequences.count>1 else { return };recordEdit()
        let removed=selected;selected=0;project.sequences.remove(at:removed);select(min(removed,project.sequences.count-1))
        status="Secuencia eliminada · puedes deshacer"
    }
    func transform(_ kind:String) {
        recordEdit()
        for r in project.slices.indices {
            let row=project.sequences[selected].cells[r]
            switch kind {
            case "Invertir": project.sequences[selected].cells[r]=row.map { !$0 }
            case "Reversa": project.sequences[selected].cells[r]=Array(row.reversed())
            case "Desplazar derecha": project.sequences[selected].cells[r]=[row.last!]+row.dropLast()
            default: project.sequences[selected].cells[r]=Array(row.dropFirst())+[row[0]]
            }
        }
        let weights=timing.weights
        switch kind {
        case "Reversa": project.sequences[selected].durations=Array(weights.reversed())
        case "Desplazar derecha": project.sequences[selected].durations=[weights.last!]+weights.dropLast()
        case "Desplazar izquierda": project.sequences[selected].durations=Array(weights.dropFirst())+[weights[0]]
        default: break
        }
        tempoChanged()
    }
    func resize(_ n: Int) {
        guard (1...256).contains(n),n != count else { return };recordEdit()
        let previousWeights=timing.weights
        var sequence=project.sequences[selected]
        for r in project.slices.indices { let old=sequence.cells[r];sequence.cells[r]=(0..<n).map { $0<old.count ? old[$0]:false } }
        sequence.durations=(0..<n).map { $0<previousWeights.count ? previousWeights[$0]:1 };project.sequences[selected]=sequence;editStep=min(editStep,n-1)
        seek(min(step,n-1))
    }
    func pattern(_ kind: String) {
        recordEdit()
        let rows = project.slices.count
        for r in 0..<rows { for c in 0..<count {
            let value: Bool
            switch kind { case "Chase": value = c % rows == r; case "Alternar": value = c % 2 == r % 2; case "Todos": value = true; case "Aleatorio": value = Bool.random(); default: value = false }
            project.sequences[selected].cells[r][c] = value
        } }
    }
    func addSequence(copy: Bool) {
        guard project.sequences.count < 128 else { return }
        recordEdit()
        project.sequences.append(Sequence(name:copy ? project.sequences[selected].name+" copia" : "Chase \(project.sequences.count+1)", cells:copy ? project.sequences[selected].cells : project.slices.map { _ in Array(repeating:false,count:count) },durations:copy ? project.sequences[selected].durations:nil,factory:copy ? project.sequences[selected].factory:nil))
        select(project.sequences.count-1)
    }
    func fail(_ error: Error) { status = error.localizedDescription; let a = NSAlert(); a.messageText = "No se pudo completar"; a.informativeText = error.localizedDescription; a.runModal() }
    func importXML() {
        let p = NSOpenPanel(); p.allowedFileTypes = ["xml"]; p.message = "Selecciona un preset de Advanced Output de Resolume"; p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let u = p.url else { return }
        do { let (w,h,s) = try loadSlices(u);try preserveBeforeReplace();recordEdit();playing=false;recovering=true;selected=0;editStep=0;project=Project(width:w,height:h,bpm:project.bpm,division:project.division,envelope:project.envelope,bezier:project.bezier,slices:s,sequences:[Sequence(name:"Chase 01",cells:s.map { _ in Array(repeating:false,count:16) })]);seek(0);recovering=false;scheduleRecovery();status="\(u.lastPathComponent) · \(s.count) slices importados" } catch { fail(error) }
    }
    func save() {
        guard validate(project) else { fail(AppError.message("Revisa el proyecto y el tempo antes de guardar."));return }
        let p = NSSavePanel(); p.nameFieldStringValue = "Mi chase"; p.allowedFileTypes=["chaselab"]
        guard p.runModal() == .OK, let u=p.url else { return }
        do { let e=JSONEncoder(); e.outputFormatting=[.prettyPrinted,.sortedKeys]; try e.encode(project).write(to:u,options:.atomic); status="Proyecto guardado" } catch { fail(error) }
    }
    func open() {
        let p=NSOpenPanel(); p.allowedFileTypes=["chaselab"]; guard p.runModal() == .OK, let u=p.url else { return }
        do { guard (try u.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) < 20_000_000 else { throw AppError.message("El proyecto supera 20 MB.") }; var loaded=try JSONDecoder().decode(Project.self,from:Data(contentsOf:u)); guard validate(loaded) else { throw AppError.message("Proyecto incompatible o dañado.") };try preserveBeforeReplace();recordEdit();loaded.version=5;playing=false;recovering=true;selected=0;editStep=0;project=loaded;reconcileLibrarySelection();seek(0);recovering=false;scheduleRecovery();status="Proyecto abierto" } catch { fail(error) }
    }
    func showOutput() {
        if let w=output { w.makeKeyAndOrderFront(nil); return }
        let w=NSWindow(contentRect:NSRect(x:100,y:100,width:960,height:540),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        w.title="ChaseLab · Salida"; w.isReleasedWhenClosed=false; w.backgroundColor = .black
        w.contentView=NSHostingView(rootView:Stage(store:self,clean:true)); w.makeKeyAndOrderFront(nil); output=w
    }
    func exportMovie() {
        guard validate(project) else { fail(AppError.message("Revisa el tempo: debe estar entre 20 y 300 BPM.")); return }
        let panel=NSSavePanel(); panel.allowedFileTypes=["mov"]; panel.nameFieldStringValue="\(project.sequences[selected].name).mov"
        guard panel.runModal() == .OK, let url=panel.url else { return }
        let p=project, s=project.sequences[selected]
        exporting=true; status="Exportando vídeo…"
        DispatchQueue.global(qos:.userInitiated).async {
            do { try renderMovie(p,s,url); DispatchQueue.main.async { self.exporting=false; self.status="Vídeo exportado · importa el MOV en Resolume como máscara" } }
            catch { DispatchQueue.main.async { self.exporting=false; self.fail(error) } }
        }
    }
}
func renderMovie(_ p: Project, _ s: Sequence, _ url: URL) throws {
    let scale=min(1, min(3840/p.width,2160/p.height))
    let w=max(2,Int(p.width*scale)/2*2), h=max(2,Int(p.height*scale)/2*2)
    let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
    let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:w,AVVideoHeightKey:h])
    let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:w,kCVPixelBufferHeightKey as String:h])
    guard writer.canAdd(input) else { throw AppError.message("El codificador de vídeo no está disponible.") }
    writer.add(input); guard writer.startWriting() else { throw writer.error ?? AppError.message("No se pudo crear el vídeo.") }; writer.startSession(atSourceTime:.zero)
    let stepDuration=60/p.bpm/p.division, timing=SequenceTiming(s)
    let frames=max(1,Int(ceil(timing.total*stepDuration*30)))
    defer { if writer.status == .writing { writer.cancelWriting() } }
    for frame in 0..<frames {
        let deadline=Date().addingTimeInterval(15)
        while !input.isReadyForMoreMediaData { guard writer.status == .writing, Date()<deadline else { throw writer.error ?? AppError.message("El codificador dejó de responder.") }; Thread.sleep(forTimeInterval:0.005) }
        try autoreleasepool {
            var pixel: CVPixelBuffer?
            guard let pool=adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil,pool,&pixel) == kCVReturnSuccess, let pixel else { throw AppError.message("No hay memoria para exportar.") }
            CVPixelBufferLockBaseAddress(pixel,[]); defer { CVPixelBufferUnlockBaseAddress(pixel,[]) }
            guard let ctx=CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:w,height:h,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue) else { throw AppError.message("No se pudo dibujar el fotograma.") }
            ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x:0,y:0,width:w,height:h)); ctx.translateBy(x:0,y:CGFloat(h)); ctx.scaleBy(x:CGFloat(w)/p.width,y: -CGFloat(h)/p.height)
            let location=timing.location(Double(frame)/30/stepDuration),step=location.step,value=level(p,location.phase)
            ctx.setFillColor(CGColor(gray:value,alpha:1))
            for r in p.slices.indices where s.cells[r][step] { let points=p.slices[r].points; ctx.beginPath(); ctx.move(to:CGPoint(x:points[0].x,y:points[0].y)); for pt in points.dropFirst() { ctx.addLine(to:CGPoint(x:pt.x,y:pt.y)) }; ctx.closePath(); ctx.fillPath() }
            guard adaptor.append(pixel,withPresentationTime:CMTime(value:Int64(frame),timescale:30)) else { throw writer.error ?? AppError.message("Error al escribir un fotograma.") }
        }
    }
    input.markAsFinished(); writer.endSession(atSourceTime:CMTime(seconds:timing.total*stepDuration,preferredTimescale:60000))
    let sem=DispatchSemaphore(value:0); writer.finishWriting { sem.signal() }; guard sem.wait(timeout:.now()+60) == .success, writer.status == .completed else { throw writer.error ?? AppError.message("No se pudo finalizar el vídeo.") }
}
let accent=Color(red:0.36,green:0.93,blue:0.77)
struct Stage: View {
    @ObservedObject var store: Store; var clean=false; var labels=false
    var body: some View {
        TimelineView(.animation(minimumInterval:1/30,paused:!store.playing)) { _ in
        GeometryReader { geo in
            let p=store.project, scale=min(geo.size.width/p.width,geo.size.height/p.height)
            let ox=(geo.size.width-p.width*scale)/2, oy=(geo.size.height-p.height*scale)/2
            ZStack {
                Color.black
                ForEach(Array(p.slices.enumerated()),id:\.element.id) { r,slice in
                    let active=p.sequences[store.selected].cells[r][store.step]
                    let path=Path { path in
                        guard let first=slice.points.first else { return }; path.move(to:CGPoint(x:ox+first.x*scale,y:oy+first.y*scale))
                        for pt in slice.points.dropFirst() { path.addLine(to:CGPoint(x:ox+pt.x*scale,y:oy+pt.y*scale)) }; path.closeSubpath()
                    }
                    path.fill(active ? (clean ? Color.white : accent).opacity(store.playing ? level(p,store.phase) : 1) : (clean ? Color.black : Color.white.opacity(0.05)))
                    if !clean {
                        path.stroke(active ? accent : Color.white.opacity(0.22),lineWidth:1)
                        if labels,let first=slice.points.first {
                            Text(slice.name).font(.system(size:9,weight:.medium)).padding(3).background(Color.black.opacity(0.7)).position(x:ox+first.x*scale+18,y:oy+first.y*scale+9).allowsHitTesting(false)
                        }
                        path.fill(Color.white.opacity(0.001)).contentShape(path).onTapGesture { store.toggle(r,store.editStep) }
                    }
                }
            }
        }.aspectRatio(store.project.width/store.project.height,contentMode:.fit)
        }
    }
}
if CommandLine.arguments.contains("--self-test") {
    do {
        let canvas=CanvasTransform(view:CGSize(width:800,height:500),project:CGSize(width:1024,height:576),zoom:1,pan:CGSize(width:30,height:-20))
        let world=Point(x:600,y:300),screen=canvas.screen(world)
        var enlarged=canvas;enlarged.pan=canvas.zoomed(to:2.5,around:screen);enlarged.zoom=2.5
        precondition(hypot(enlarged.screen(world).x-screen.x,enlarged.screen(world).y-screen.y)<0.000001)
        let fit=CanvasTransform(view:CGSize(width:800,height:500),project:CGSize(width:1024,height:576),zoom:1,pan:.zero)
        precondition(abs(fit.screen(Point(x:512,y:288)).x-400)<0.000001 && abs(fit.screen(Point(x:512,y:288)).y-250)<0.000001)
        print("PASS: canvas fit and cursor-anchored zoom preserve the target point")
        try runFactoryTests(directory:FileManager.default.temporaryDirectory.appendingPathComponent("factory-test-"+UUID().uuidString))
        try runBezierTests(directory:FileManager.default.temporaryDirectory.appendingPathComponent("bezier-test-"+UUID().uuidString))
        try runOutputSyncTests()
        try runEnvelopeLibraryTests()
        try runEnvelopePresetTests()
        do {
            var project=demoProject();project.sequences[0].durations=Array(repeating:2,count:16)
            let data=try LiveBridge.catalogData(project:project,session:"fixture",revision:7)
            let catalog=try JSONSerialization.jsonObject(with:data) as! [String:Any]
            let sequences=catalog["sequences"] as! [[String:Any]],bits=Data(base64Encoded:sequences[0]["bits"] as! String)!
            precondition(bits.count==16 && bits[0]==1 && bits[7]==128 && bits[8]==1)
            precondition((catalog["envelope"] as! [Double]).count==1025 && (catalog["width"] as! Double)==1920)
            precondition((sequences[0]["durations"] as! [Double]).allSatisfy{$0==2})
            print("PASS: Player catalog bit packing, IDs, durations, dimensions and envelope LUT")
        }
        var clock=ArenaClock()
        clock.receive(bpm:120,barPhase:0.95,time:100,now:100)
        clock.receive(bpm:120,barPhase:0.05,time:100.2,now:100.2)
        precondition(abs(clock.beats-4.2)<0.00001)
        precondition(abs(clock.position(at:100.3,division:2,count:16)!-8.8)<0.00001)
        clock.receive(bpm:60,barPhase:0.1,time:100.3,now:100.3)
        precondition(abs(clock.position(at:100.4,division:4,count:32)!-18)<0.00001)
        let oldTime=clock.sampleTime
        clock.receive(bpm:120,barPhase:0.9,time:99,now:100.4);precondition(clock.sampleTime==oldTime)
        precondition(clock.position(at:101,division:2,count:16)==nil)
        clock.receive(bpm:120,barPhase:0.5,time:110,now:110)
        precondition(clock.position(at:110,division:2,count:16) != nil)
        clock.reset();precondition(clock.position(at:110,division:2,count:16)==nil)
        print("PASS: bar wrap, phase interpolation, tempo change, stale/out-of-order samples, reacquisition")
        let p=demoProject(); precondition(validate(p)); let data=try JSONEncoder().encode(p); let decoded=try JSONDecoder().decode(Project.self,from:data); precondition(decoded.sequences[0].cells == p.sequences[0].cells)
        precondition(level("Fade out",0.5) == 0.5)
        let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("chaselab-recovery-test-\(UUID().uuidString)",isDirectory:true)
        defer { try? FileManager.default.removeItem(at:temporary) }
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
        let malformed=temporary.appendingPathComponent("partial-invalid.xml")
        try Data("<root><Slice><InputRect><v x='0' y='0'/><v x='1' y='0'/><v x='0' y='1'/></InputRect></Slice><Slice><InputRect><v x='NaN' y='0'/><v x='1' y='0'/><v x='0' y='1'/></InputRect></Slice></root>".utf8).write(to:malformed)
        var rejected=false;do { _=try loadSlices(malformed) } catch { rejected=true };precondition(rejected,"Partial imports must fail instead of silently dropping a slice")
        try Data("<root><CurrentCompositionTextureSize width='bad' height='100'/><Slice><InputRect><v x='0' y='0'/><v x='1' y='0'/><v x='0' y='1'/></InputRect></Slice></root>".utf8).write(to:malformed)
        rejected=false;do { _=try loadSlices(malformed) } catch { rejected=true };precondition(rejected)
        print("PASS: invalid slices and malformed resolution reject the entire import")
        try runEditingTests(directory:temporary.appendingPathComponent("editing"))
        let storage=RecoveryStorage(directory:temporary)
        let snap=SessionSnapshot(project:p,selected:0,step:3,followArenaBpm:true,savedAt:Date())
        try storage.save(snap);precondition(storage.load()?.step==3)
        var newer=snap;newer.step=7;try storage.save(newer);precondition(storage.load()?.step==7)
        try Data("corrupt".utf8).write(to:temporary.appendingPathComponent("recovery.json"));precondition(storage.load()?.step==3)
        try storage.preserve(snap);let history=try FileManager.default.contentsOfDirectory(atPath:temporary.appendingPathComponent("Snapshots").path);precondition(history.count==1)
        let editor=Store(recoveryStorage:storage,startTimer:false)
        let original=editor.project.sequences[0].cells
        editor.toggle(0,0);precondition(editor.project.sequences[0].cells[0][0] != original[0][0])
        editor.undoEdit();precondition(editor.project.sequences[0].cells==original)
        editor.redoEdit();precondition(editor.project.sequences[0].cells[0][0] != original[0][0])
        editor.addSequence(copy:true);precondition(editor.selected==1 && editor.project.sequences.count==2)
        let duplicateID=editor.project.sequences[1].id
        editor.moveSequence(-1);precondition(editor.selected==0 && editor.project.sequences[0].id==duplicateID)
        editor.deleteSequence();precondition(editor.project.sequences.count==1 && validate(editor.project))
        editor.undoEdit();precondition(editor.project.sequences.count==2 && editor.project.sequences[0].id==duplicateID)
        let before=editor.project.sequences[0].cells
        editor.transform("Desplazar derecha");editor.transform("Desplazar izquierda");precondition(editor.project.sequences[0].cells==before)
        editor.transform("Reversa");editor.transform("Reversa");precondition(editor.project.sequences[0].cells==before)
        editor.transform("Invertir");editor.transform("Invertir");precondition(editor.project.sequences[0].cells==before)
        editor.resize(4);precondition(editor.count==4 && editor.step<4 && validate(editor.project))
        editor.undoEdit();precondition(editor.count==16)
        editor.recoveryWork?.cancel()
        print("PASS: sequence duplicate/reorder/delete, undo/redo, shift/reverse/invert, resize")
        let bridgeDirectory=temporary.appendingPathComponent("isolated-bridge",isDirectory:true)
        let modalStore=Store(recoveryStorage:storage,startTimer:true,liveBridge:LiveBridge(directory:bridgeDirectory))
        modalStore.toggleLive();modalStore.play()
        let end=Date().addingTimeInterval(0.4)
        while Date()<end { RunLoop.main.run(mode:RunLoop.Mode("NSModalPanelRunLoopMode"),before:end) }
        modalStore.timer?.invalidate();modalStore.recoveryWork?.cancel()
        let frameData=try Data(contentsOf:bridgeDirectory.appendingPathComponent("frame.json"))
        let frame=try JSONSerialization.jsonObject(with:frameData) as! [String:Any]
        precondition((frame["sequence"] as? Int ?? 0)>4,"Bridge stalled in modal run-loop mode")
        print("PASS: bridge keeps sending through modal run-loop mode")
        let beatNow=Date().timeIntervalSince1970
        let ack:[String:Any]=["time":beatNow,"sequence":frame["sequence"]!,"bpm":60.0,"barPhase":0.25,"beatTime":beatNow]
        try JSONSerialization.data(withJSONObject:ack).write(to:bridgeDirectory.appendingPathComponent("receiver.json"),options:.atomic)
        modalStore.followArenaBpm=true;modalStore.followArenaPhase=true
        for _ in 0..<3 { modalStore.tick() }
        precondition(modalStore.project.bpm==60 && modalStore.step==2)
        modalStore.recoveryWork?.cancel()
        print("PASS: receiver BPM and beat timestamp drive the editor position")
        if let arg=CommandLine.arguments.firstIndex(of:"--xml"), CommandLine.arguments.count > arg+1 { let (w,h,s)=try loadSlices(URL(fileURLWithPath:CommandLine.arguments[arg+1])); print("XML OK: \(s.count) slices, \(w)x\(h)") }
        if let arg=CommandLine.arguments.firstIndex(of:"--timed-movie"),CommandLine.arguments.count>arg+1 {
            var movie=demoProject();movie.envelope="Corte"
            movie.sequences[0].cells=movie.slices.indices.map { r in (0..<4).map { c in r==c } };movie.sequences[0].durations=[0.5,2,1,4]
            try renderMovie(movie,movie.sequences[0],URL(fileURLWithPath:CommandLine.arguments[arg+1]));print("TIMED MOV OK: 1.875 seconds")
        }
        if let arg=CommandLine.arguments.firstIndex(of:"--movie"), CommandLine.arguments.count > arg+1 { try renderMovie(p,p.sequences[0],URL(fileURLWithPath:CommandLine.arguments[arg+1])); print("MOV OK") }
        print("PASS: validation, JSON roundtrip, envelope, recovery, corrupt-file fallback, snapshot history"); exit(0)
    } catch { print(error); exit(1) }
}
let application=NSApplication.shared
class Delegate: NSObject, NSApplicationDelegate {
    var window:NSWindow!; let store=Store()
    func applicationDidFinishLaunching(_ notification:Notification) {
        let menu=NSMenu(); let item=NSMenuItem(); menu.addItem(item); let sub=NSMenu(); let install=NSMenuItem(title:"Instalar efectos en Arena…",action:#selector(Delegate.installPlugins),keyEquivalent:"");install.target=self;sub.addItem(install);sub.addItem(.separator());sub.addItem(withTitle:"Salir de ChaseLab",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); item.submenu=sub
        let editItem=NSMenuItem(); menu.addItem(editItem); let edit=NSMenu(title:"Editar"); for (title,key,action) in [("Deshacer","z",#selector(UndoManager.undo)),("Cortar","x",#selector(NSText.cut(_:))),("Copiar","c",#selector(NSText.copy(_:))),("Pegar","v",#selector(NSText.paste(_:))),("Seleccionar todo","a",#selector(NSText.selectAll(_:)))] { edit.addItem(withTitle:title,action:action,keyEquivalent:key) }; editItem.submenu=edit; NSApplication.shared.mainMenu=menu
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="ChaseLab · Secuenciador visual"; window.contentView=NSHostingView(rootView:Content(store:store)); window.center(); window.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps:true)
    }
    @objc func installPlugins() { PluginInstaller.run() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard store.saveRecovery() else {
            let alert=NSAlert();alert.messageText="No se pudo guardar el proyecto";alert.informativeText=store.recoveryStatus;alert.runModal();return .terminateCancel
        }
        if store.exporting {
            let alert=NSAlert();alert.messageText="Hay un vídeo exportándose";alert.informativeText="Espera a que termine antes de cerrar.";alert.runModal();return .terminateCancel
        }
        return .terminateNow
    }
}
let delegate=Delegate(); application.delegate=delegate; application.setActivationPolicy(.regular); application.run()
