// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation

@main struct ClockSimulation {
    static func main() {
        var clock=ArenaClock()
        var time=1_800_000_000.0
        var beats=0.68
        var bpm=123.45
        clock.receive(bpm:bpm,barPhase:beats/4,time:time,now:time)
        var maxError=0.0
        for i in 1...20_000 {
            let next=time+0.03+Double(i%5)*0.001
            beats+=(next-time)*bpm/60
            time=next
            if i%333==0 { bpm=[60.0,128.39,180.0,300.0,20.0][(i/333)%5] }
            let bar=Double(Float((beats/4)-floor(beats/4)))
            clock.receive(bpm:bpm,barPhase:bar,time:time,now:time+0.04)
            let now=time+0.04
            for division in [1.0,2.0,4.0] {
                for count in [4,8,16,32] {
                    let raw=(beats+(now-time)*bpm/60)*division
                    let expected=raw-Double(count)*floor(raw/Double(count))
                    let actual=clock.position(at:now,division:division,count:count)!
                    let error=abs(actual-expected)
                    let circularError=min(error,Double(count)-error)
                    maxError=max(maxError,circularError)
                    precondition(circularError<0.00001,"Drift in relative phase clock")
                }
            }
        }
        print(String(format:"PASS: 20,000 phase samples, 60 tempo changes, all divisions/lengths; max position error %.8f steps",maxError))
    }
}
