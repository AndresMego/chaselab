// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
#import <Foundation/Foundation.h>
#include <OpenGL/OpenGL.h>
#include <FFGLSDK.h>
#include <dlfcn.h>
#include <thread>
#include <unistd.h>
#include <iostream>
#include <ctime>
#include <cmath>
#include <mach/mach.h>
static void require(bool value,const char* message) {if(!value){std::cerr<<"FAIL: "<<message<<"\n";exit(1);}}
int main(int argc,char** argv) { @autoreleasepool {
 require(argc==3 || argc==4,"plugin and mode required, optional soak seconds");bool source=atoi(argv[2]);int soakSeconds=argc==4 ? atoi(argv[3]):0;require(soakSeconds>=0 && soakSeconds<=180,"soak duration");
 NSString* testDirectory=[NSString stringWithFormat:@"/private/tmp/chaselab-test-%u-%d",getuid(),getpid()];setenv("CHASELAB_BRIDGE_DIR",testDirectory.fileSystemRepresentation,1);
 CGLPixelFormatAttribute attrs[]={kCGLPFAOpenGLProfile,(CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,kCGLPFAAccelerated,(CGLPixelFormatAttribute)0};
 CGLPixelFormatObj format;GLint count;require(CGLChoosePixelFormat(attrs,&format,&count)==kCGLNoError,"pixel format");CGLContextObj context;require(CGLCreateContext(format,nullptr,&context)==kCGLNoError,"context");CGLDestroyPixelFormat(format);CGLSetCurrentContext(context);
 void* lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!lib) std::cerr<<dlerror()<<"\n";require(lib,"dlopen");auto main=(FF_Main_FuncPtr)dlsym(lib,"plugMain");require(main,"entry point");FFMixed arg{};
 auto info=(PluginInfoStruct*)main(FF_GET_INFO,arg,nullptr).PointerValue;require(info && info->PluginType==(source ? FF_SOURCE:FF_EFFECT),"plugin metadata");require(main(FF_INITIALISE_V2,arg,nullptr).UIntValue==FF_SUCCESS,"initialise");
 GLuint fbo,tex,inputTex;glGenTextures(1,&tex);glBindTexture(GL_TEXTURE_2D,tex);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,64,64,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glBindTexture(GL_TEXTURE_2D,0);glGenFramebuffers(1,&fbo);glBindFramebuffer(GL_FRAMEBUFFER,fbo);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex,0);require(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,"framebuffer");
 std::vector<unsigned char> image(64*64*4);for(size_t i=0;i<image.size();i+=4){image[i]=128;image[i+1]=64;image[i+2]=32;image[i+3]=255;}
 glGenTextures(1,&inputTex);glBindTexture(GL_TEXTURE_2D,inputTex);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,64,64,0,GL_RGBA,GL_UNSIGNED_BYTE,image.data());glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glBindTexture(GL_TEXTURE_2D,0);
 FFGLViewportStruct viewport{0,0,64,64};arg.PointerValue=&viewport;auto instance=main(FF_INSTANTIATE_GL,arg,nullptr).PointerValue;require(instance && instance!=(void*)(uintptr_t)FF_FAIL,"instantiate GL");
 FFGLTextureStruct input{64,64,64,64,inputTex};FFGLTextureStruct* inputPtr=&input;ProcessOpenGLStruct process{source ? 0u:1u,source ? nullptr:&inputPtr,fbo};
 NSString* dir=testDirectory;[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil];
 auto write=[&](NSArray* polygon,int seq,double intensity=1.0){NSDictionary* d=@{@"version":@1,@"sequence":@(seq),@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@(intensity),@"enabled":@YES,@"polygons":@[polygon]};NSData* data=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([data writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"write fixture");std::this_thread::sleep_for(std::chrono::milliseconds(80));};
 auto render=[&](){glViewport(0,0,64,64);glBindFramebuffer(GL_FRAMEBUFFER,fbo);arg.PointerValue=&process;require(main(FF_PROCESS_OPENGL,arg,instance).UIntValue==FF_SUCCESS,"process GL");glFinish();require(glGetError()==GL_NO_ERROR,"GL error/state");};
 auto pixel=[&](int x,int y,int red,int alpha){unsigned char rgba[4];glReadPixels(x,y,1,1,GL_RGBA,GL_UNSIGNED_BYTE,rgba);if(abs((int)rgba[0]-red)>2 || abs((int)rgba[3]-alpha)>2) std::cerr<<"pixel "<<x<<","<<y<<" actual "<<(int)rgba[0]<<","<<(int)rgba[3]<<" expected "<<red<<","<<alpha<<"\n";require(abs((int)rgba[0]-red)<=2 && abs((int)rgba[3]-alpha)<=2,"pixel mismatch");};
 SetBeatinfoStruct beat{123.45f,0.25f};arg.PointerValue=&beat;require(main(FF_SET_BEATINFO,arg,instance).UIntValue==FF_SUCCESS,"beat info callback");
 write(@[@[@-1,@-1],@[@1,@-1],@[@1,@0],@[@0,@0],@[@0,@1],@[@-1,@1]],1);render();pixel(16,16,source?255:128,255);pixel(48,16,source?255:128,255);pixel(16,48,source?255:128,255);pixel(48,48,0,0);
 std::this_thread::sleep_for(std::chrono::milliseconds(100));
 NSDictionary* ack=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"receiver.json"]] options:0 error:nil];require(ack && std::abs([ack[@"bpm"] floatValue]-123.45)<0.01 && std::abs([ack[@"barPhase"] floatValue]-0.25)<0.001,"BPM feedback");
 require([ack[@"geometryBuilds"] unsignedLongLongValue]==1 && [ack[@"frameReads"] unsignedLongLongValue]==1,"first geometry build and unchanged file read once");
 write(@[@[@-1,@-1],@[@1,@-1],@[@1,@0],@[@0,@0],@[@0,@1],@[@-1,@1]],2,0.5);render();pixel(16,16,source?128:64,source?128:128);pixel(48,48,0,0);
 std::this_thread::sleep_for(std::chrono::milliseconds(100));
 ack=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"receiver.json"]] options:0 error:nil];require([ack[@"geometryBuilds"] unsignedLongLongValue]==1 && [ack[@"frameReads"] unsignedLongLongValue]==2,"intensity update reuses geometry and unchanged file is skipped");
 write(@[@[@0,@0],@[@1,@0],@[@1,@1],@[@0,@1]],3);render();pixel(16,16,0,0);pixel(48,48,source?255:128,255);
 // Stress the supported 16,384 active vertices, then animate intensity without rebuilding.
 NSMutableArray* circle=[NSMutableArray array];for(int i=0;i<1024;++i){double angle=i*2*M_PI/1024;[circle addObject:@[@(0.9*cos(angle)),@(0.9*sin(angle))]];}
 NSMutableArray* many=[NSMutableArray array];for(int i=0;i<16;++i)[many addObject:circle];
 auto writeMany=[&](int sequence,double intensity){NSDictionary* d=@{@"version":@1,@"sequence":@(sequence),@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@(intensity),@"enabled":@YES,@"polygons":many};NSData* bytes=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([bytes writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"write stress fixture");};
 clock_t cpuStart=clock();writeMany(4,1.0);
 const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(4);
 do {
     std::this_thread::sleep_for(std::chrono::milliseconds(10));render();
     ack=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"receiver.json"]] options:0 error:nil];
 } while([ack[@"sequence"] unsignedLongLongValue]!=4 && std::chrono::steady_clock::now()<deadline);
 require([ack[@"sequence"] unsignedLongLongValue]==4 && [ack[@"geometryBuilds"] unsignedLongLongValue]==3,"maximum active vertices accepted");pixel(32,32,source?255:128,255);pixel(0,0,0,0);
 for(int i=0;i<30;++i){writeMany(5+i,(i%2)?1.0:0.5);std::this_thread::sleep_for(std::chrono::milliseconds(35));render();}
 std::this_thread::sleep_for(std::chrono::milliseconds(100));
 ack=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"receiver.json"]] options:0 error:nil];
 require([ack[@"sequence"] unsignedLongLongValue]>=32 && [ack[@"geometryBuilds"] unsignedLongLongValue]==3,"large geometry reused across intensity animation");
 std::cout<<"STRESS: 16,384 active vertices, 30 intensity updates, one geometry build; process CPU "<<double(clock()-cpuStart)/CLOCKS_PER_SEC<<" s\n";
 if(soakSeconds>0) {
     auto resident=[](){mach_task_basic_info_data_t info{};mach_msg_type_number_t count=MACH_TASK_BASIC_INFO_COUNT;require(task_info(mach_task_self(),MACH_TASK_BASIC_INFO,(task_info_t)&info,&count)==KERN_SUCCESS,"read own memory");return uint64_t(info.resident_size);};
     uint64_t warmMemory=0,peakMemory=0;int frames=0;
     const auto start=std::chrono::steady_clock::now(),end=start+std::chrono::seconds(soakSeconds);auto next=start;
     while(std::chrono::steady_clock::now()<end) {
         @autoreleasepool {
             writeMany(100+frames,0.25*(1+(frames/10)%4));
             next+=std::chrono::milliseconds(33);std::this_thread::sleep_until(next);render();
             unsigned char center[4];glReadPixels(32,32,1,1,GL_RGBA,GL_UNSIGNED_BYTE,center);require(center[0]>=(source?62:30) && center[0]<=(source?255:130) && center[3]>=62,"stable center intensity");pixel(0,0,0,0);
             if(frames==100) warmMemory=resident();if(frames>=100)peakMemory=std::max(peakMemory,resident());++frames;
         }
     }
     require(frames>=soakSeconds*10,"soak render progress");
     if(warmMemory)require(peakMemory<warmMemory+64*1024*1024,"resident growth below 64 MiB after warmup");
     std::cout<<"SOAK: "<<soakSeconds<<" s, "<<frames<<" frames, max active vertices, no GL/pixel errors; RSS warm/peak "<<warmMemory/1048576.0<<"/"<<peakMemory/1048576.0<<" MiB\n";
 }
 std::this_thread::sleep_for(std::chrono::milliseconds(1150));render();pixel(16,16,source?0:128,source?0:255);pixel(48,48,source?0:128,source?0:255);
 arg.PointerValue=nullptr;require(main(FF_DEINSTANTIATE_GL,arg,instance).UIntValue==FF_SUCCESS,"deinstantiate");main(FF_DEINITIALISE,arg,nullptr);dlclose(lib);
 [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:@"frame.json"] error:nil];[[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:@"receiver.json"] error:nil];
 std::cout<<"PASS "<<(source?"source":"effect")<<": FFGL ABI, OpenGL 4.1, concave slices, live edits, orientation, alpha, BPM feedback, geometry cache/intensity updates, unchanged file skipping, stale fail-safe\n";
 CGLSetCurrentContext(nullptr);CGLDestroyContext(context);
}}
