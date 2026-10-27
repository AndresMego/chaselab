// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import SwiftUI

struct SequenceGrid:View {
    @ObservedObject var store:Store
    @GestureState private var drawing=false
    func durationLabel(_ value:Double)->String {
        switch value { case 0.25:return "¼×";case 0.5:return "½×";case 1:return "";default:return "\(Int(value))×" }
    }
    var body:some View {
        GeometryReader { viewport in
        ScrollView([.horizontal,.vertical]) {
            VStack(spacing:4) {
                HStack(spacing:4) {
                    Text("SLICE / PASO").font(.system(size:9,weight:.medium)).foregroundColor(.secondary).frame(width:120,height:34,alignment:.leading)
                    ForEach(0..<store.count,id:\.self) { c in
                        Button { store.selectEditStep(c) } label: {
                            VStack(spacing:2) {
                                Text(String(format:"%02d",c+1)).font(.system(size:10,design:.monospaced))
                                Text(durationLabel(store.timing.weights[c])).font(.system(size:8,design:.monospaced))
                            }.frame(width:30,height:34).foregroundColor(store.editStep==c ? accent:.secondary)
                                .background(RoundedRectangle(cornerRadius:3).fill(store.editStep==c ? accent.opacity(0.14):.clear))
                        }.buttonStyle(.plain).accessibilityLabel("Seleccionar paso \(c+1)")
                    }
                }
                VStack(spacing:4) {
                    ForEach(Array(store.project.slices.enumerated()),id:\.element.id) { r,s in
                        HStack(spacing:4) {
                            Text(s.name).font(.caption).lineLimit(1).frame(width:120,height:25,alignment:.leading)
                            ForEach(0..<store.count,id:\.self) { c in
                                RoundedRectangle(cornerRadius:3)
                                    .fill(store.project.sequences[store.selected].cells[r][c] ? accent:Color.white.opacity(c%4==0 ? 0.13:0.07))
                                    .frame(width:30,height:25)
                                    .overlay(RoundedRectangle(cornerRadius:3).stroke(store.step==c && store.playing ? Color(red:1,green:0.65,blue:0.25):(store.editStep==c ? accent.opacity(0.55):.clear),lineWidth:1))
                                    .accessibilityElement(children:.ignore)
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel("\(s.name), paso \(c+1), \(store.project.sequences[store.selected].cells[r][c] ? "activo":"apagado")")
                                    .accessibilityAction { store.toggle(r,c) }
                            }
                        }
                    }
                }.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).updating($drawing) { _,active,_ in active=true }.onChanged { value in
                        store.paint(x:value.location.x,y:value.location.y)
                    }.onEnded { _ in store.endPaint() })
                    .help("Arrastra desde una celda apagada para encender; desde una encendida para borrar. Un deshacer revierte todo el trazo.")
            }.fixedSize(horizontal:true,vertical:true).frame(minWidth:viewport.size.width,minHeight:viewport.size.height,alignment:.topLeading)
        }.onChange(of:drawing) { active in if !active { store.endPaint() } }.onDisappear { store.endPaint() }
        }
    }
}
