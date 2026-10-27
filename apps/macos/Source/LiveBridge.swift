// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation
import Darwin

struct ReceiverFeedback {
    var bpm: Double?
    var barPhase: Double?
    var time: Double
    var beatTime:Double?
}

/// One atomic local snapshot at a time; rendering never waits on the writer.
final class LiveBridge {
    private let queue = DispatchQueue(label:"local.chaselab.bridge",qos:.userInteractive)
    private let catalogQueue=DispatchQueue(label:"local.chaselab.catalog",qos:.utility)
    private var envelopeSamples:[UUID:(curve:BezierEnvelope,values:[Double])]=[:]
    private var inFlight=false
    private let flightLock=NSLock()
    private var number:UInt64=0
    private var catalogInFlight=false
    private var session=UUID().uuidString
    private let directory:URL
    private(set) var started=Date().timeIntervalSince1970
    init(directory:URL?=nil) { self.directory=directory ?? URL(fileURLWithPath:"/private/tmp/chaselab-\(getuid())",isDirectory:true) }
    func prepare() throws {
        let fm=FileManager.default
        if !fm.fileExists(atPath:directory.path) { try fm.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]) }
        var st=stat()
        guard lstat(directory.path,&st)==0, (st.st_mode & S_IFMT)==S_IFDIR, st.st_uid==getuid(), (st.st_mode & 0o077)==0 else { throw AppError.message("La carpeta temporal de conexión no es privada o no pertenece a tu usuario.") }
        started=Date().timeIntervalSince1970;session=UUID().uuidString
    }
    func send(project:Project,selected:Int,step:Int,phase:Double,playing:Bool,enabled:Bool,completion:@escaping(String?)->Void) {
        flightLock.lock();let busy=inFlight;flightLock.unlock()
        guard !busy else { return }
        var polygons=[[[Double]]]()
        var total=0
        if enabled {
            for r in project.slices.indices where project.sequences[selected].cells[r][step] {
                let points=project.slices[r].points
                total += points.count
                guard total<=16384 else { completion("El montaje activo supera 16 384 vértices.");return }
                polygons.append(points.map { [2*$0.x/project.width-1,1-2*$0.y/project.height] })
            }
        }
        number &+= 1
        let snapshot:[String:Any] = ["version":1,"session":session,"sequence":number,"time":Date().timeIntervalSince1970,"intensity":playing ? level(project,phase):1.0,"enabled":enabled,"playing":playing,"polygons":polygons,"step":step,"sequenceID":project.sequences[selected].id.uuidString,"phase":phase]
        flightLock.lock();inFlight=true;flightLock.unlock()
        queue.async {
            var message:String?
            do { let data=try JSONSerialization.data(withJSONObject:snapshot);try data.write(to:self.directory.appendingPathComponent("frame.json"),options:.atomic) }
            catch { message=error.localizedDescription }
            self.flightLock.lock();self.inFlight=false;self.flightLock.unlock()
            DispatchQueue.main.async { completion(message) }
        }
    }
    /// Separate catalog changes from the small per-frame snapshot. All encoding runs off the UI thread.
    @discardableResult func publishCatalog(project:Project,revision:UInt64,envelopes:[NamedEnvelope]=[],completion:@escaping(String?)->Void)->Bool {
        flightLock.lock();let busy=catalogInFlight;if !busy {catalogInFlight=true};flightLock.unlock()
        guard !busy else {return false}
        let currentSession=session
        catalogQueue.async {
            var message:String?
            do {
                for entry in envelopes where self.envelopeSamples[entry.id]?.curve != entry.curve {
                    self.envelopeSamples[entry.id]=(entry.curve,(0...1024).map{entry.curve.value(Double($0)/1024)})
                }
                let ids=Set(envelopes.map(\.id));self.envelopeSamples=self.envelopeSamples.filter{ids.contains($0.key)}
                let data=try Self.catalogData(project:project,session:currentSession,revision:revision,envelopes:envelopes,envelopeLUTs:self.envelopeSamples.mapValues{ $0.values })
                try data.write(to:self.directory.appendingPathComponent("catalog.json"),options:.atomic)
            } catch {message=error.localizedDescription}
            self.flightLock.lock();self.catalogInFlight=false;self.flightLock.unlock()
            DispatchQueue.main.async {completion(message)}
        }
        return true
    }
    static func catalogData(project:Project,session:String,revision:UInt64,envelopes:[NamedEnvelope]=[],envelopeLUTs:[UUID:[Double]]=[:])throws->Data {
        let rows=project.slices.count,stride=(rows+7)/8
        let sequences:[[String:Any]]=project.sequences.map { sequence in
            let count=sequence.cells[0].count
            var bits=Data(repeating:0,count:count*stride)
            for r in 0..<rows {for c in 0..<count where sequence.cells[r][c] {bits[c*stride+r/8] |= UInt8(1 << (r%8))}}
            return ["id":sequence.id.uuidString,"name":sequence.name,"count":count,"bits":bits.base64EncodedString(),"durations":SequenceTiming(sequence).weights]
        }
        let polygons=project.slices.map {slice in slice.points.map{[2*$0.x/project.width-1,1-2*$0.y/project.height]}}
        let value:[String:Any]=["version":1,"session":session,"revision":revision,"width":project.width,"height":project.height,"polygons":polygons,"sequences":sequences,"envelopes":envelopes.map{entry -> [String:Any] in ["id":entry.id.uuidString,"name":entry.name,"values":envelopeLUTs[entry.id] ?? (0...1024).map{i in entry.curve.value(Double(i)/1024)}]},"envelope":(0...1024).map{level(project,Double($0)/1024)}]
        return try JSONSerialization.data(withJSONObject:value)
    }
    func playerStatus()->String {
        guard let urls=try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) else {return "Player: sin comprobación de resolución"}
        var active=0,warnings:[String]=[]
        for url in urls.prefix(256) where url.lastPathComponent.hasPrefix("player-") && url.pathExtension=="json" {
            guard let data=try? Data(contentsOf:url),data.count<4096,let v=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let time=v["time"] as? Double,abs(Date().timeIntervalSince1970-time)<2,let width=v["inputWidth"] as? Int,let height=v["inputHeight"] as? Int else {continue}
            active += 1
            if (v["resolutionMismatch"] as? Bool)==true {warnings.append("\(width) × \(height)")}
        }
        if !warnings.isEmpty {return "Revisar resolución: entrada Player \(Set(warnings).sorted().joined(separator:", ")). Guarda Advanced Output y sincroniza el montaje."}
        return active>0 ? "Player: resolución coincide · \(active) instancia(s)":"Player: sin comprobación de resolución"
    }
    func feedback()->ReceiverFeedback? {
        guard let data=try? Data(contentsOf:directory.appendingPathComponent("receiver.json")),data.count<4096,let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any], let time=value["time"] as? Double,let sequence=value["sequence"] as? UInt64,time>=started,Date().timeIntervalSince1970-time >= -0.05,Date().timeIntervalSince1970-time<1,sequence<=number,number-sequence<90 else { return nil }
        var bpm:Double?,phase:Double?,sampleTime:Double?
        if let tempo=value["bpm"] as? Double, tempo.isFinite, (20...300).contains(tempo), let beatTime=value["beatTime"] as? Double, abs(Date().timeIntervalSince1970-beatTime)<0.5 {
            bpm=tempo;sampleTime=beatTime
            if let p=value["barPhase"] as? Double,p.isFinite,(0..<1).contains(p) { phase=p }
        }
        return ReceiverFeedback(bpm:bpm,barPhase:phase,time:time,beatTime:sampleTime)
    }
}
