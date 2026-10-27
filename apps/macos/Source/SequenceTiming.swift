// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation

struct SequenceTiming {
    static let choices=[0.25,0.5,1.0,2.0,4.0]
    let weights:[Double]
    init(_ sequence:Sequence) { weights=sequence.durations ?? Array(repeating:1,count:sequence.cells.first?.count ?? 0) }
    var total:Double { weights.reduce(0,+) }
    func offset(_ step:Int)->Double { weights.prefix(max(0,step)).reduce(0,+) }
    func location(_ position:Double)->(step:Int,phase:Double) {
        guard !weights.isEmpty,total>0,position.isFinite else { return (0,0) }
        let wrapped=position-total*floor(position/total)
        var start=0.0
        for i in weights.indices {
            if wrapped<start+weights[i] { return (i,max(0,min(1,(wrapped-start)/weights[i]))) }
            start+=weights[i]
        }
        return (0,0)
    }
}

struct GridCell:Equatable { var row:Int;var column:Int }
enum GridLayout {
    static let labelWidth=120.0,cellWidth=30.0,cellHeight=25.0,gap=4.0
    static func cell(x:Double,y:Double,rows:Int,columns:Int)->GridCell? {
        guard x.isFinite,y.isFinite,rows>0,columns>0 else { return nil }
        let localX=x-labelWidth-gap
        guard localX>=0,y>=0 else { return nil }
        let c=Int(floor(localX/(cellWidth+gap))),r=Int(floor(y/(cellHeight+gap)))
        guard r<rows,c<columns,localX-Double(c)*(cellWidth+gap)<cellWidth,y-Double(r)*(cellHeight+gap)<cellHeight else { return nil }
        return GridCell(row:r,column:c)
    }
    /// Fill cells crossed between mouse events, including fast strokes.
    static func line(from a:GridCell,to b:GridCell)->[GridCell] {
        var x=a.column,y=a.row
        let dx=abs(b.column-x),sx=x<b.column ? 1:-1,dy = -abs(b.row-y),sy=y<b.row ? 1:-1
        var error=dx+dy,result:[GridCell]=[]
        while true {
            result.append(GridCell(row:y,column:x));if x==b.column && y==b.row { return result }
            let twice=2*error
            if twice>=dy { error+=dy;x+=sx }
            if twice<=dx { error+=dx;y+=sy }
        }
    }
}
