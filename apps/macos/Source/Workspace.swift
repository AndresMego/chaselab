// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import SwiftUI

private let panel=Color(red:0.075,green:0.095,blue:0.12)
private let amber=Color(red:1,green:0.65,blue:0.25)

struct EnvelopePreview:View {
    var name:String
    var body:some View {
        Canvas { context,size in
            var curve=Path()
            for i in 0...80 {
                let phase=Double(i)/80
                let point=CGPoint(x:phase*size.width,y:4+(1-level(name,phase))*(size.height-8))
                if i==0 { curve.move(to:point) } else { curve.addLine(to:point) }
            }
            context.stroke(curve,with:.color(accent),lineWidth:2)
        }.accessibilityLabel("Curva \(name)")
    }
}

struct Content:View {
    @ObservedObject var store:Store
    @AppStorage("workspace.matrix08") private var matrix=false
    @StateObject private var viewport=PreviewViewport()
    @AppStorage("workspace.inspector") private var inspector=true
    @AppStorage("workspace.labels") private var labels=false
    @AppStorage("workspace.factoryGuides") private var factoryGuides=false
    @AppStorage("workspace.tool") private var tool="Patrones"
    private var editingFactoryGrid:Bool {tool=="Factory" && factoryGuides}
    private var cycle:String { (store.timing.total/store.project.division).formatted(.number.precision(.fractionLength(0...4))) }
    var body:some View {
        VStack(spacing:0) {
            topBar
            Divider()
            HStack(spacing:0) {
                library.frame(width:180).background(panel)
                Divider()
                VStack(spacing:0) {
                    transport.padding(12)
                    Divider()
                    VSplitView {
                        VStack(spacing:0) {
                            canvasBar.padding(10).background(panel.opacity(0.6))
                            PreviewCanvas(store:store,viewport:viewport,names:labels,factoryMode:editingFactoryGrid)
                                .clipped()
                            HStack {
                                Text(editingFactoryGrid ? "Cuadrícula Factory · selecciona una división para editarla":(viewport.hover.isEmpty ? "Elige un paso y pinta sobre los slices":viewport.hover))
                                Spacer()
                                Text(viewport.tool=="Mano" ? "Arrastra para mover · ⌘ rueda para zoom":(editingFactoryGrid ? "Arrastra divisiones · Central: mover · ⌘ rueda: zoom":"Arrastra para pintar · Central: mover · ⌘ rueda: zoom"))
                            }.font(.system(size:10)).foregroundColor(.secondary).padding(8)
                        }.frame(minHeight:220,maxHeight:.infinity)
                        VStack(alignment:.leading,spacing:0) {
                            stepStrip.padding(.vertical,8).background(panel.opacity(0.7))
                            Divider()
                            editBar.padding(10)
                            if matrix { SequenceGrid(store:store).padding(.horizontal,10).padding(.bottom,6) }
                        }.frame(minHeight:matrix ? 240:100,idealHeight:matrix ? 300:100,maxHeight:matrix ? 440:100)
                    }
                }.frame(minWidth:660,maxWidth:.infinity)
                if inspector {
                    Divider()
                    tools.frame(width:210).background(panel)
                }
            }
            Divider()
            HStack(spacing:8) {
                Circle().fill(store.liveEnabled ? accent:.gray).frame(width:6,height:6)
                Text(store.liveEnabled ? store.liveStatus:"Arena desconectado")
                Divider().frame(height:12)
                Text(store.status).lineLimit(1)
                Spacer()
                Text(store.recoveryStatus).lineLimit(1)
            }.font(.system(size:10)).foregroundColor(.secondary).padding(.horizontal,12).frame(height:26)
        }.frame(minWidth:1080,minHeight:720).background(Color(red:0.045,green:0.06,blue:0.08)).preferredColorScheme(.dark).tint(accent)
    }
    func heading(_ text:String)->some View { Text(text).font(.system(size:10,weight:.semibold)).tracking(1).foregroundColor(.secondary) }
    var topBar:some View {
        HStack(spacing:12) {
            Text("CHASE / LAB").font(.system(size:14,weight:.black,design:.monospaced)).foregroundColor(accent)
            Text("0.14").font(.caption).foregroundColor(.secondary)
            Divider().frame(height:20)
            Menu("Archivo") {
                Button("Abrir proyecto…",action:store.open).keyboardShortcut("o")
                Button("Guardar proyecto…",action:store.save).keyboardShortcut("s")
                Divider()
                Button("Importar slices XML…",action:store.importXML)
                Button("Exportar vídeo MOV…",action:store.exportMovie).disabled(store.exporting)
            }.frame(width:80)
            Text("\(Int(store.project.width)) × \(Int(store.project.height)) · \(store.project.slices.count) slices").font(.caption).foregroundColor(.secondary)
            Spacer()
            Toggle(isOn:$matrix) { Label("Matriz",systemImage:"square.grid.3x3") }.toggleStyle(.button).help("Abrir edición de varios pasos a la vez")
            Toggle(isOn:$inspector) { Label("Herramientas",systemImage:"sidebar.right") }.toggleStyle(.button)
            Button(action:store.toggleLive) { Label(store.liveEnabled ? "Conectado":"Conectar Arena",systemImage:"dot.radiowaves.left.and.right") }.tint(store.liveEnabled ? accent:.gray)
        }.controlSize(.small).padding(.horizontal,14).frame(height:44)
    }
    var canvasBar:some View {
        HStack(spacing:8) {
            Picker("Herramienta",selection:$viewport.tool) {
                Label("Editar",systemImage:"pencil.tip").tag("Editar")
                Label("Mano",systemImage:"hand.draw").tag("Mano")
            }.pickerStyle(.segmented).labelsHidden().frame(width:160)
            Divider().frame(height:18)
            Button { viewport.zoom=max(0.25,viewport.zoom/1.25) } label: { Image(systemName:"minus.magnifyingglass") }.help("Alejar")
            Text("\(Int(viewport.zoom*100))%").font(.system(size:11,design:.monospaced)).frame(width:42).accessibilityLabel("Zoom \(Int(viewport.zoom*100)) por ciento")
            Button { viewport.zoom=min(8,viewport.zoom*1.25) } label: { Image(systemName:"plus.magnifyingglass") }.help("Acercar")
            Button("Ajustar",action:viewport.fit).help("Centrar el montaje y ajustar al lienzo")
            Spacer(minLength:0)
            if tool=="Factory" {
                Toggle("Grilla",isOn:$factoryGuides).toggleStyle(.checkbox).font(.caption).help("Mostrar y editar las guías de Factory. Ocultarlas permite pintar slices sin cambiar el patrón.")
            }
            Toggle("Nombres",isOn:$labels).toggleStyle(.checkbox).font(.caption)
        }.controlSize(.small)
    }
    var library:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { heading("SECUENCIAS");Spacer();Text("\(store.project.sequences.count)").font(.caption).foregroundColor(.secondary) }.padding(.top,14)
            ScrollView {
                VStack(spacing:4) {
                    ForEach(Array(store.project.sequences.enumerated()),id:\.element.id) { i,sequence in
                        Button { store.select(i) } label: {
                            HStack(alignment:.top,spacing:8) {
                                Text(String(format:"%02d",i+1)).font(.system(.caption,design:.monospaced)).foregroundColor(store.selected==i ? accent:.secondary)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(sequence.name).font(.system(size:12,weight:.medium)).lineLimit(2)
                                    Text("\(sequence.cells.first?.count ?? 0) pasos").font(.system(size:10)).foregroundColor(.secondary)
                                }
                                Spacer(minLength:0)
                            }.padding(9).frame(maxWidth:.infinity,alignment:.leading).background(RoundedRectangle(cornerRadius:5).fill(store.selected==i ? accent.opacity(0.13):Color.clear))
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button { store.addSequence(copy:false) } label: { Label("Nueva",systemImage:"plus") }
                Button { store.addSequence(copy:true) } label: { Image(systemName:"plus.square.on.square") }.help("Duplicar secuencia")
            }
            HStack {
                Button { store.moveSequence(-1) } label: { Image(systemName:"arrow.up") }.disabled(store.selected==0).help("Subir secuencia")
                Button { store.moveSequence(1) } label: { Image(systemName:"arrow.down") }.disabled(store.selected==store.project.sequences.count-1).help("Bajar secuencia")
                Spacer()
                Button(action:store.deleteSequence) { Image(systemName:"trash") }.disabled(store.project.sequences.count<2).help("Eliminar secuencia · puedes deshacer")
            }
            Divider()
            Button("Guardar proyecto…",action:store.save).keyboardShortcut("s")
            Button("Ventana de salida",action:store.showOutput)
        }.controlSize(.small).padding(12)
    }
    var transport:some View {
        VStack(alignment:.leading,spacing:10) {
            TextField("Nombre de secuencia",text:$store.project.sequences[store.selected].name).font(.system(size:17,weight:.semibold)).textFieldStyle(.plain)
            HStack(spacing:10) {
                Button { store.seek(0) } label: { Image(systemName:"backward.end.fill") }.help("Volver al inicio")
                Button(action:store.play) { Label(store.playing ? "Pausa":"Play",systemImage:store.playing ? "pause.fill":"play.fill").frame(width:62) }.tint(accent).keyboardShortcut(.space,modifiers:[])
                TextField("BPM",value:$store.project.bpm,format:.number.precision(.fractionLength(0...2))).frame(width:54).disabled(store.followArenaBpm).onSubmit { store.project.bpm=min(300,max(20,store.project.bpm.isFinite ? store.project.bpm:120));store.tempoChanged() }
                Text("BPM").font(.caption).foregroundColor(.secondary)
                Picker("División",selection:$store.project.division) { Text("1/4").tag(1.0);Text("1/8").tag(2.0);Text("1/16").tag(4.0) }.labelsHidden().frame(width:72).onChange(of:store.project.division) { _ in store.tempoChanged() }
                Spacer(minLength:0)
                Text("\(cycle) tiempos").font(.caption).foregroundColor(.secondary)
                Text(String(format:"%02d / %02d",store.step+1,store.count)).font(.system(size:17,weight:.medium,design:.monospaced)).foregroundColor(store.playing ? amber:accent)
            }.controlSize(.small)
        }
    }
    var stepStrip:some View {
        ScrollView(.horizontal) {
            HStack(spacing:5) {
                ForEach(0..<store.count,id:\.self) { c in
                    Button { store.selectEditStep(c) } label: {
                        VStack(spacing:3) {
                            Text(String(format:"%02d",c+1)).font(.system(size:11,weight:.semibold,design:.monospaced))
                            if store.timing.weights[c] != 1 { Text(SequenceGrid(store:store).durationLabel(store.timing.weights[c])).font(.system(size:8)) }
                            Capsule().fill(store.playing && store.step==c ? amber:Color.clear).frame(height:3)
                        }.padding(.top,6).frame(width:34,height:36)
                            .background(RoundedRectangle(cornerRadius:4).fill(store.editStep==c ? accent.opacity(0.22):Color.white.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius:4).stroke(store.editStep==c ? accent:Color.clear))
                    }.buttonStyle(.plain).accessibilityLabel("Editar paso \(c+1)")
                    .contextMenu {
                        Button("Copiar paso") { store.selectEditStep(c);store.copyStep() }
                        Button("Pegar paso") { store.selectEditStep(c);store.pasteStep() }.disabled(!store.canPasteStep)
                        Divider()
                        ForEach(SequenceTiming.choices,id:\.self) { weight in
                            Button("Duración \(weight.formatted())×") { store.selectEditStep(c);store.setStepDuration(weight) }
                        }
                    }
                }
            }.padding(.horizontal,10)
        }.frame(height:42)
    }
    var editBar:some View {
        HStack(spacing:8) {
            Text("Paso \(store.editStep+1)").font(.system(size:11,weight:.semibold,design:.monospaced)).foregroundColor(accent).frame(width:52,alignment:.leading)
            Button(action:store.copyStep) { Label("Copiar",systemImage:"doc.on.doc") }.help("Copiar paso con duración · ⇧⌘C").keyboardShortcut("c",modifiers:[.command,.shift])
            Button(action:store.pasteStep) { Label("Pegar",systemImage:"doc.on.clipboard") }.disabled(!store.canPasteStep).help("Pegar paso con duración · ⇧⌘V").keyboardShortcut("v",modifiers:[.command,.shift])
            Picker("Duración",selection:Binding(get:{store.timing.weights[store.editStep]},set:store.setStepDuration)) {
                Text("¼×").tag(0.25);Text("½×").tag(0.5);Text("1×").tag(1.0);Text("2×").tag(2.0);Text("4×").tag(4.0)
            }.frame(width:125)
            Spacer(minLength:0)
            Button(action:store.undoEdit) { Image(systemName:"arrow.uturn.backward") }.disabled(store.undoStates.isEmpty).help("Deshacer trazo o edición")
            Button(action:store.redoEdit) { Image(systemName:"arrow.uturn.forward") }.disabled(store.redoStates.isEmpty).help("Rehacer edición")
            HStack(spacing:6) {
                Button { store.resize(store.count-1) } label: { Image(systemName:"minus") }.disabled(store.count<=1).help("Quitar el último paso · puedes deshacer").accessibilityLabel("Quitar paso")
                Text("\(store.count) pasos").monospacedDigit().frame(minWidth:55)
                Button { store.resize(store.count+1) } label: { Image(systemName:"plus") }.disabled(store.count>=256).help("Añadir un paso vacío al final").accessibilityLabel("Añadir paso")
            }
        }.controlSize(.small)
    }
    var tools:some View {
        VStack(alignment:.leading,spacing:12) {
            Picker("Herramientas",selection:$tool) { ForEach(["Factory","Patrones","Envolvente","Arena"],id:\.self) { Text($0) } }.labelsHidden()
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    if tool=="Factory" {
                        FactoryPanel(store:store)
                    } else if tool=="Patrones" {
                        heading("GENERAR PATRÓN")
                        Text("Se aplica a la secuencia seleccionada. Puedes deshacer.").font(.caption).foregroundColor(.secondary)
                        ForEach(["Chase","Alternar","Todos","Aleatorio","Vaciar"],id:\.self) { name in
                            Button { store.pattern(name) } label: { HStack { Text(name);Spacer();Image(systemName: name=="Chase" ? "arrow.right":name=="Aleatorio" ? "shuffle":name=="Vaciar" ? "square":"square.grid.2x2") }.frame(maxWidth:.infinity).padding(.vertical,3) }
                        }
                        Divider();heading("TRANSFORMAR")
                        ForEach(["Invertir","Reversa","Desplazar izquierda","Desplazar derecha"],id:\.self) { name in Button(name) { store.transform(name) } }
                    } else if tool=="Envolvente" {
                        EnvelopePanel(store:store)
                    } else {
                        heading("MONTAJE DE ARENA")
                        Text(store.project.arenaPreset ?? "Sin vincular").font(.caption)
                        Button("Detectar montaje activo…",action:store.linkArenaOutput)
                        Toggle("Sincronizar al guardar",isOn:Binding(get:{store.syncOutput},set:{store.syncOutput=$0;store.arenaOutput.reset()})).disabled(store.project.arenaPreset==nil)
                        Text(store.outputSyncStatus).font(.caption).foregroundColor(.secondary)
                        Text("Recoge cambios guardados en Advanced Output. Conserva patrones y respalda el proyecto antes de modificar el montaje.").font(.caption).foregroundColor(.secondary)
                        Divider()
                        heading("CONEXIÓN EN VIVO")
                        Text(store.arenaResolutionStatus).font(.caption).foregroundColor(.secondary)
                        Text(store.liveStatus).foregroundColor(store.liveEnabled ? accent:.secondary)
                        Button(store.liveEnabled ? "Desconectar":"Conectar con Arena",action:store.toggleLive)
                        Divider()
                        Toggle("Seguir BPM de Arena",isOn:$store.followArenaBpm)
                        Text(store.arenaTempoStatus).font(.caption).foregroundColor(.secondary)
                        Toggle("Sincronizar compás",isOn:$store.followArenaPhase).disabled(!store.followArenaBpm)
                        Text(store.arenaPhaseStatus).font(.caption).foregroundColor(.secondary)
                        Button("Reiniciar conteo",action:store.alignBar)
                        Divider()
                        Text("En Arena: añade ChaseLab Player a Composition. Control Editor sigue esta app; Control Arena permite elegir Sequence y animar Step.").font(.caption).foregroundColor(.secondary)
                        Button(store.exporting ? "Exportando…":"Exportar vídeo MOV…",action:store.exportMovie).disabled(store.exporting)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            Spacer(minLength:0)
            Divider()
            Label("Selección de edición",systemImage:"square").foregroundColor(accent)
            Label("Paso en reproducción",systemImage:"play.fill").foregroundColor(amber)
        }.font(.system(size:12)).controlSize(.small).padding(12)
    }
}
