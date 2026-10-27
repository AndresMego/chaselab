// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation

/// Relative bar clock: FFGL exposes phase within four beats, not phrase/bar numbers.
struct ArenaClock {
    private(set) var beats:Double=0
    private(set) var sampleTime:Double=0
    private(set) var bpm:Double=120
    private(set) var hasSample=false
    mutating func reset() { hasSample=false }
    mutating func receive(bpm:Double,barPhase:Double,time:Double,now:Double) {
        guard bpm.isFinite,(20...300).contains(bpm),barPhase.isFinite,(0..<1).contains(barPhase),time.isFinite,now.isFinite,now-time >= -0.05,now-time<=0.5 else { return }
        guard !hasSample || time>sampleTime else { return }
        let within=barPhase*4
        if hasSample {
            let predicted=beats+(time-sampleTime)*self.bpm/60
            beats=within+4*((predicted-within)/4).rounded()
        } else { beats=within }
        sampleTime=time;self.bpm=bpm;hasSample=true
    }
    func position(at now:Double,division:Double,count:Int,cycleLength:Double?=nil)->Double? {
        guard hasSample,now.isFinite,now-sampleTime >= -0.05,now-sampleTime<=0.5,[1.0,2.0,4.0].contains(division),(1...256).contains(count) else { return nil }
        let length=cycleLength ?? Double(count)
        guard length.isFinite,length>0,length<=1024 else { return nil }
        let value=(beats+max(0,now-sampleTime)*bpm/60)*division
        return value-length*floor(value/length)
    }
}
