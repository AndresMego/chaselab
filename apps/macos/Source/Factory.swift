// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation
import SwiftUI

struct FactorySettings:Codable,Equatable {
    var direction="Horizontal"
    var block=1,modulo=0
    var flipX=false,flipY=false,mirrorX=false,mirrorY=false,shuffle=false
    var seed:UInt64=1
    var x:[Double]=[],y:[Double]=[]
    static let directions=["Horizontal","Vertical","Filas","Columnas","Aleatorio"]
    var valid:Bool {
        Self.directions.contains(direction) && (1...256).contains(block) && (0...256).contains(modulo) && x.count<=255 && y.count<=255 && [x,y].allSatisfy { a in a.allSatisfy{$0.isFinite && abs($0)<1e7} && zip(a,a.dropFirst()).allSatisfy{$0<$1} }
    }
    static func center(_ s:Slice)->Point {
        let xs=s.points.map(\.x),ys=s.points.map(\.y)
        return Point(x:(xs.min()!+xs.max()!)/2,y:(ys.min()!+ys.max()!)/2)
    }
    static func automatic(_ slices:[Slice])->FactorySettings {
        func borders(_ values:[Double])->[Double] {
            var centers:[Double]=[]
            for value in values.sorted() { if centers.last.map({abs($0-value)>0.5}) ?? true { centers.append(value) } }
            return zip(centers,centers.dropFirst()).map { ($0+$1)/2 }
        }
        let points=slices.map(center)
        return FactorySettings(x:borders(points.map(\.x)),y:borders(points.map(\.y)))
    }
}

private struct FactoryRandom:RandomNumberGenerator {
    var state:UInt64
    mutating func next()->UInt64 { state=state &+ 0x9e3779b97f4a7c15;var z=state;z=(z ^ (z>>30)) &* 0xbf58476d1ce4e5b9;z=(z ^ (z>>27)) &* 0x94d049bb133111eb;return z ^ (z>>31) }
}
struct FactoryResult {
    var settings:FactorySettings
    var cells:[[Bool]]
    var steps:Int { cells.first?.count ?? 1 }
}
enum FactoryEngine {
    static func generate(_ slices:[Slice],_ input:FactorySettings)->FactoryResult {
        var f=input
        let cols=f.x.count+1,rows=f.y.count+1
        let coords=slices.map { slice -> (x:Int,y:Int) in
            let p=FactorySettings.center(slice)
            var x=f.x.filter{$0<p.x}.count,y=f.y.filter{$0<p.y}.count
            if f.flipX { x=cols-1-x };if f.flipY { y=rows-1-y }
            return (x,y)
        }
        var groups:[[Int]]=[]
        if f.direction=="Filas" || f.direction=="Columnas" {
            let keys=Set(coords.map { f.direction=="Filas" ? $0.y:$0.x }).sorted()
            groups=keys.map { key in slices.indices.filter { (f.direction=="Filas" ? coords[$0].y:coords[$0].x)==key } }
        } else {
            var order=Array(slices.indices).sorted { a,b in
                let ca=coords[a],cb=coords[b]
                let primaryA=f.direction=="Vertical" ? ca.x:ca.y,primaryB=f.direction=="Vertical" ? cb.x:cb.y
                if primaryA != primaryB { return primaryA<primaryB }
                let secondaryA=f.direction=="Vertical" ? ca.y:ca.x,secondaryB=f.direction=="Vertical" ? cb.y:cb.x
                return secondaryA==secondaryB ? a<b:secondaryA<secondaryB
            }
            if f.direction=="Aleatorio" { var rng=FactoryRandom(state:f.seed);order.shuffle(using:&rng) }
            groups=order.map { [$0] }
        }
        f.block=max(1,min(f.block,max(1,groups.count)))
        let natural=max(1,(groups.count+f.block-1)/f.block)
        f.modulo=max(0,min(f.modulo,natural))
        if f.modulo==1 { f.modulo=0 }
        let count=f.modulo>1 ? f.modulo:natural
        var cells=Array(repeating:Array(repeating:false,count:count),count:slices.count)
        for (g,indices) in groups.enumerated() {
            let step=(g/f.block)%count
            for r in indices {
                cells[r][step]=true
                if f.mirrorX || f.mirrorY {
                    let c=coords[r]
                    for j in slices.indices {
                        let target=coords[j]
                        let xMatch=target.x==c.x || (f.mirrorX && target.x==cols-1-c.x)
                        let yMatch=target.y==c.y || (f.mirrorY && target.y==rows-1-c.y)
                        if xMatch && yMatch { cells[j][step]=true }
                    }
                }
            }
        }
        if f.shuffle {
            var rng=FactoryRandom(state:f.seed ^ 0xa57b)
            var order=Array(0..<count);order.shuffle(using:&rng)
            cells=cells.map { row in order.map { row[$0] } }
        }
        return FactoryResult(settings:f,cells:cells)
    }
}

extension Store {
    var factory:FactorySettings { project.sequences[selected].factory ?? FactorySettings.automatic(project.slices) }
    func updateFactory(_ settings:FactorySettings,record:Bool=true) {
        guard settings.valid else { return }
        let result=FactoryEngine.generate(project.slices,settings)
        if record { recordEdit() }
        project.sequences[selected].factory=result.settings
        project.sequences[selected].cells=result.cells
        project.sequences[selected].durations=nil
        editStep=min(editStep,result.steps-1);seek(min(step,result.steps-1))
        status="Factory · \(result.steps) pasos · puedes deshacer"
    }
    func changeFactory(_ change:(inout FactorySettings)->Void) { var settings=factory;change(&settings);updateFactory(settings) }
    func resetFactoryGrid() { var settings=factory;let auto=FactorySettings.automatic(project.slices);settings.x=auto.x;settings.y=auto.y;updateFactory(settings) }
}

struct FactoryPanel:View {
    @ObservedObject var store:Store
    func flag(_ name:String,_ key:WritableKeyPath<FactorySettings,Bool>)->some View {
        Toggle(name,isOn:Binding(get:{store.factory[keyPath:key]},set:{ value in store.changeFactory{$0[keyPath:key]=value} })).toggleStyle(.button)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("FACTORY").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Picker("Dirección",selection:Binding(get:{store.factory.direction},set:{value in store.changeFactory{$0.direction=value}})) {
                ForEach(FactorySettings.directions,id:\.self) { Text($0) }
            }.labelsHidden()
            HStack { flag("Flip X",\.flipX);flag("Flip Y",\.flipY) }
            Stepper("Block  \(store.factory.block)",value:Binding(get:{store.factory.block},set:{value in store.changeFactory{$0.block=value}}),in:1...store.project.slices.count)
            Stepper(store.factory.modulo==0 ? "Modulo  OFF":"Modulo  \(store.factory.modulo)",onIncrement:{store.changeFactory{$0.modulo=$0.modulo==0 ? 2:$0.modulo+1}},onDecrement:{store.changeFactory{$0.modulo=$0.modulo<=2 ? 0:$0.modulo-1}})
            HStack { flag("Mirror X",\.mirrorX);flag("Mirror Y",\.mirrorY) }
            flag("Shuffle",\.shuffle)
            Button("Otra variación") { store.changeFactory{$0.seed=UInt64.random(in:0...UInt64.max)} }
            Divider()
            Text("\(store.factory.x.count+1) columnas × \(store.factory.y.count+1) filas").font(.caption).foregroundColor(.secondary)
            Text("Activa Grilla en el lienzo para editar las guías. Ocúltala para pintar slices. Las divisiones se calculan entre centros; no son los bordes de los slices.").font(.caption).foregroundColor(.secondary)
            Button("Reset Grid",action:store.resetFactoryGrid).help("Recalcular guías y regenerar esta secuencia · puedes deshacer")
            Divider()
            Button("Generar ahora") { store.updateFactory(store.factory) }
            Button("Crear copia Factory") { store.addSequence(copy:true);store.updateFactory(store.factory) }
            Text("Cambiar un ajuste regenera la secuencia y su longitud. Los pasos vuelven a 1×. Deshacer recupera el patrón anterior.").font(.caption).foregroundColor(.secondary)
            Text("Salir de Factory permite afinar los slices manualmente. Entrar de nuevo conserva esas ediciones hasta cambiar un ajuste.").font(.caption).foregroundColor(.secondary)
        }
    }
}
