// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation
import AVFoundation
import AppKit
let asset=AVURLAsset(url:URL(fileURLWithPath:CommandLine.arguments[1]))
precondition(abs(asset.duration.seconds-1.875)<0.01,"Variable-duration movie length")
let generator=AVAssetImageGenerator(asset:asset)
generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
for (time,column) in [(0.05,0),(0.3,1),(0.7,2),(1.1,3)] {
 let image=try generator.copyCGImage(at:CMTime(seconds:time,preferredTimescale:600),actualTime:nil)
 let w=image.width,h=image.height
 var bytes=[UInt8](repeating:0,count:w*h*4)
 bytes.withUnsafeMutableBytes { buffer in
  let ctx=CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
 }
 var counts=[Int](repeating:0,count:4)
 for y in 0..<h { for x in 0..<w where bytes[(y*w+x)*4]>200 { counts[min(3,x/(w/4))]+=1 } }
 precondition(counts[column]>150000 && counts.enumerated().allSatisfy { $0.offset==column || $0.element<1000 },"Incorrect held step at \(time): \(counts)")
}
print("PASS: H.264 duration 1.875 seconds and decoded masks follow 0.5x/2x/1x/4x step lengths")
