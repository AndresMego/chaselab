// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
#import <Foundation/Foundation.h>
#include <OpenGL/OpenGL.h>
#include <FFGLSDK.h>
#include <dlfcn.h>
#include <thread>
#include <iostream>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <fstream>

static float asFloat(FFMixed m){float f;memcpy(&f,&m.UIntValue,sizeof(f));return f;}
#include <unistd.h>
static void require(bool v,const char* m){if(!v){std::cerr<<"FAIL: "<<m<<"\n";exit(1);}}
int main(int argc,char**argv){@autoreleasepool{
 require(argc==3,"plugin path and source mode");bool source=atoi(argv[2])!=0;
 char temp[]="/private/tmp/chaselab-mapper-test.XXXXXX";require(mkdtemp(temp),"private directory");setenv("CHASELAB_BRIDGE_DIR",temp,1);NSString*dir=[NSString stringWithUTF8String:temp];
 CGLPixelFormatAttribute attrs[]={kCGLPFAOpenGLProfile,(CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,kCGLPFAAccelerated,(CGLPixelFormatAttribute)0};CGLPixelFormatObj fmt;GLint n;CGLContextObj ctx;require(CGLChoosePixelFormat(attrs,&fmt,&n)==kCGLNoError,"format");require(CGLCreateContext(fmt,nullptr,&ctx)==kCGLNoError,"context");CGLDestroyPixelFormat(fmt);CGLSetCurrentContext(ctx);
 void*lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!lib)std::cerr<<dlerror()<<"\n";require(lib,"dlopen");auto entry=(FF_Main_FuncPtr)dlsym(lib,"plugMain");require(entry,"entry");FFMixed a{};require(entry(FF_INITIALISE_V2,a,nullptr).UIntValue==FF_SUCCESS,"initialise");require(entry(FF_GET_NUM_PARAMETERS,a,nullptr).UIntValue==24,"twenty-four parameters");a.UIntValue=1;require(entry(FF_GET_PARAMETER_TYPE,a,nullptr).UIntValue==FF_TYPE_OPTION,"Scaling option");
 GLuint target,out,input;glGenTextures(1,&out);glBindTexture(GL_TEXTURE_2D,out);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,64,64,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glGenFramebuffers(1,&target);glBindFramebuffer(GL_FRAMEBUFFER,target);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,out,0);require(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,"FBO");
 std::vector<unsigned char> image(128*64*4,255);auto upload=[&](int alpha){for(int y=0;y<32;++y)for(int x=0;x<64;++x){int i=(y*128+x)*4;image[i]=std::lround(255.0*x/63);image[i+1]=std::lround(255.0*y/31);image[i+2]=32;image[i+3]=alpha;}glBindTexture(GL_TEXTURE_2D,input);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,128,64,0,GL_RGBA,GL_UNSIGNED_BYTE,image.data());glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glBindTexture(GL_TEXTURE_2D,0);};glGenTextures(1,&input);upload(255);
 FFGLTextureStruct texture{64,32,128,64,input};FFGLTextureStruct*ptr=&texture;ProcessOpenGLStruct process{source?0u:1u,source?nullptr:&ptr,target};FFGLViewportStruct vp{0,0,64,64};a.PointerValue=&vp;void*instance=entry(FF_INSTANTIATE_GL,a,nullptr).PointerValue;require(instance && instance!=(void*)(uintptr_t)FF_FAIL,"instantiate");
 auto set=[&](int index,float value){SetParameterStruct s{};s.ParameterNumber=index;memcpy(&s.NewParameterValue.UIntValue,&value,sizeof(value));a.PointerValue=&s;require(entry(FF_SET_PARAMETER,a,instance).UIntValue==FF_SUCCESS,"parameter");};
 int seq=0;NSArray*polygons=@[@[@[@-1,@-1],@[@0,@-1],@[@0,@0],@[@-1,@0]],@[@[@0.25,@0],@[@1,@0],@[@1,@1],@[@0.25,@1]]];
 auto write=[&](float intensity,bool enabled){NSDictionary*d=@{@"version":@1,@"sequence":@(++seq),@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@(intensity),@"enabled":@(enabled),@"polygons":polygons};NSData*data=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([data writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"fixture");std::this_thread::sleep_for(std::chrono::milliseconds(60));};
 auto render=[&](){glBindFramebuffer(GL_FRAMEBUFFER,target);glViewport(0,0,64,64);a.PointerValue=&process;require(entry(FF_PROCESS_OPENGL,a,instance).UIntValue==FF_SUCCESS,"render");glFinish();require(glGetError()==GL_NO_ERROR,"GL state/error");};
 auto sample=[&](int x,int y,int r,int g,int alpha){unsigned char p[4];glReadPixels(x,y,1,1,GL_RGBA,GL_UNSIGNED_BYTE,p);if(abs(p[0]-r)>3||abs(p[1]-g)>3||abs(p[3]-alpha)>3){std::cerr<<"at "<<x<<","<<y<<": "<<(int)p[0]<<","<<(int)p[1]<<","<<(int)p[3]<<" expected "<<r<<","<<g<<","<<alpha<<"\n";require(false,"pixel");}};
 auto expected=[&](int x,int y,int mode,double bx,double by,double bw,double bh,float level=1,int alpha=255){double u=(x+.5)/64,v=(y+.5)/64;if(mode){u=((x+.5)-bx)/bw;v=((y+.5)-by)/bh;if(mode==1){double aspect=bw/bh;if(2>aspect)u=(u-.5)*(aspect/2)+.5;else v=(v-.5)*(2/aspect)+.5;}}int sx=std::clamp((int)floor(u*64),0,63),sy=std::clamp((int)floor(v*32),0,31);sample(x,y,lround(lround(255.0*sx/63)*level),lround(lround(255.0*sy/31)*level),lround(alpha*level));};


 NSMutableArray*flat=[NSMutableArray array],*low=[NSMutableArray array];for(int i=0;i<=1024;++i){[flat addObject:@1];[low addObject:@0.25];}
 NSDictionary*seqA=@{@"id":@"A",@"name":@"First",@"count":@1,@"bits":@"Aw==",@"durations":@[@1]};
 NSMutableDictionary*catalog=[@{@"version":@1,@"session":@"outliner",@"width":@64,@"height":@(source?64:32),@"polygons":polygons,@"sequences":@[seqA],@"envelope":flat,@"envelopes":@[@{@"id":@"soft",@"name":@"Soft",@"values":low}]}mutableCopy];
 auto writeCatalog=[&](){NSData*d=[NSJSONSerialization dataWithJSONObject:catalog options:0 error:nil];require([d writeToFile:[dir stringByAppendingPathComponent:@"catalog.json"] options:NSDataWritingAtomic error:nil],"catalog");std::this_thread::sleep_for(std::chrono::milliseconds(80));};
 auto heartbeat=[&](){NSDictionary*d=@{@"version":@1,@"session":@"outliner",@"sequence":@(++seq),@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@1,@"enabled":@YES,@"polygons":polygons};NSData*b=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([b writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"frame");std::this_thread::sleep_for(std::chrono::milliseconds(40));};
 auto alpha=[&](int x,int y){unsigned char p[4];glReadPixels(x,y,1,1,GL_RGBA,GL_UNSIGNED_BYTE,p);return(int)p[3];};
 auto hash=[&](){std::vector<unsigned char>px(64*64*4);glReadPixels(0,0,64,64,GL_RGBA,GL_UNSIGNED_BYTE,px.data());uint64_t value=1469598103934665603ull;for(auto x:px)value=(value^x)*1099511628211ull;return value;};
 writeCatalog();heartbeat();set(2,4);render();sample(1,8,255,255,255);sample(3,8,255,255,255);sample(4,8,0,0,0);sample(16,16,0,0,0);sample(34,16,0,0,0);
 glEnable(GL_CULL_FACE);glEnable(GL_DEPTH_TEST);glEnable(GL_SCISSOR_TEST);glScissor(0,0,0,0);glEnable(GL_STENCIL_TEST);glColorMask(GL_FALSE,GL_FALSE,GL_FALSE,GL_FALSE);render();sample(1,8,255,255,255);GLboolean masks[4];glGetBooleanv(GL_COLOR_WRITEMASK,masks);require(glIsEnabled(GL_CULL_FACE)&&glIsEnabled(GL_DEPTH_TEST)&&glIsEnabled(GL_SCISSOR_TEST)&&glIsEnabled(GL_STENCIL_TEST)&&!masks[0]&&!masks[3],"host GL clipping/depth/culling/write masks restored");glDisable(GL_CULL_FACE);glDisable(GL_DEPTH_TEST);glDisable(GL_SCISSOR_TEST);glDisable(GL_STENCIL_TEST);glColorMask(GL_TRUE,GL_TRUE,GL_TRUE,GL_TRUE);
 if(!source){set(22,1);render();expected(16,16,0,0,0,32,32);expected(34,16,0,0,0,32,32);set(22,0);}
 set(18,0);set(19,1);set(20,1);set(21,.5);render();sample(16,16,128,0,128);sample(1,8,255,255,255);set(7,.5);render();sample(1,8,191,128,191);set(7,1);set(21,0);
 set(2,8);set(8,1);render();int outer=alpha(1,12),inner=alpha(6,12);require(outer>inner&&inner>0,"Feather fades inward");set(8,0);set(1,1);set(3,1);render();sample(16,16,255,255,255);set(3,.25);render();sample(16,16,0,0,0);sample(1,8,255,255,255);set(1,0);set(2,4);
 catalog[@"polygons"]=@[@[@[@-1,@-1],@[@1,@-1],@[@1,@0],@[@0,@0],@[@0,@1],@[@-1,@1]]];catalog[@"sequences"]=@[@{@"id":@"A",@"name":@"First",@"count":@1,@"bits":@"AQ==",@"durations":@[@1]}];writeCatalog();heartbeat();render();sample(30,40,255,255,255);sample(33,40,0,0,0);sample(48,48,0,0,0);
 std::cout<<"PASS: pixel width, inward-only concave stroke, transparent interior/outside, Feather, Filled mode and premultiplied background composition\n";
 set(9,1);set(13,.2);set(10,0);render();auto firstHash=hash();set(10,.25);render();require(hash()!=firstHash,"Phase moves stroke");set(15,1);set(16,1);set(11,.6);set(12,.6);set(14,3);render();set(13,0);render();sample(30,40,0,0,0);
 set(13,1);set(11,0);set(12,0);set(17,1);render();sample(30,40,64,64,64);
 catalog[@"envelopes"]=@[@{@"id":@"full",@"name":@"Full",@"values":flat},@{@"id":@"soft",@"name":@"Renamed Soft",@"values":low}];writeCatalog();heartbeat();render();a.UIntValue=17;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==2,"Envelope stable ID");sample(30,40,64,64,64);
 auto ack=[&](){NSData*d=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"receiver.json"]];return [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];};
 std::this_thread::sleep_for(std::chrono::milliseconds(300));render();std::this_thread::sleep_for(std::chrono::milliseconds(300));auto uploads=[ack()[@"gpuUploads"] unsignedLongLongValue];heartbeat();for(int i=0;i<20;++i){set(10,i/20.f);set(4,i/20.f);render();}std::this_thread::sleep_for(std::chrono::milliseconds(300));require([ack()[@"gpuUploads"] unsignedLongLongValue]==uploads,"Phase and color reuse geometry");
 set(9,0);set(4,0);set(7,1);set(2,0);render();sample(30,40,0,0,0);set(2,4);render();set(23,0);render();if(source)sample(34,16,0,0,0);else expected(34,16,0,0,0,32,32);set(23,1);
 std::this_thread::sleep_for(std::chrono::milliseconds(1100));render();if(source)sample(34,16,0,0,0);else expected(34,16,0,0,0,32,32);heartbeat();render();sample(30,40,255,255,255);
 NSData*bad=[NSJSONSerialization dataWithJSONObject:@{@"version":[NSNull null],@"enabled":[NSNull null]} options:0 error:nil];[bad writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil];std::this_thread::sleep_for(std::chrono::milliseconds(70));render();if(source)sample(34,16,0,0,0);else expected(34,16,0,0,0,32,32);heartbeat();render();sample(30,40,255,255,255);
 std::cout<<"PASS: animation Phase/Fan/Randomise/Count/directions, zero Length, named envelope identity, no uploads for 20 phase/color changes, Amount and stale safety\n";
 // Regression: broad animated Filled strokes must not jump across nearest-edge diagonals.
 catalog[@"polygons"]=polygons;catalog[@"sequences"]=@[seqA];NSMutableArray*ramp=[NSMutableArray array];for(int i=0;i<=1024;++i)[ramp addObject:@(i/1024.f)];catalog[@"envelope"]=ramp;writeCatalog();heartbeat();
 set(1,1);set(3,1);set(9,1);set(10,.9);set(11,0);set(12,0);set(13,.4);set(14,1);set(15,0);set(16,0);set(17,0);set(22,0);render();
 int diagonalJump=abs(alpha(12,13)-alpha(13,12));std::cout<<"Filled diagonal jump: "<<diagonalJump<<" / 255\n";
 if(const char*path=getenv("CHASELAB_TEST_IMAGE")){std::vector<unsigned char>px(64*64*4);glReadPixels(0,0,64,64,GL_RGBA,GL_UNSIGNED_BYTE,px.data());std::ofstream image(path,std::ios::binary);image<<"P6\n64 64\n255\n";for(int y=63;y>=0;--y)for(int x=0;x<64;++x)image.write((char*)&px[(y*64+x)*4],3);}
 require(diagonalJump<32,"Filled animation blends across adjacent edge projections");
 set(9,0);render();sample(12,13,255,255,255);sample(13,12,255,255,255);sample(34,16,0,0,0);
 std::cout<<"PASS: Filled animated corner continuity and static fill unchanged\n";
 entry(FF_DEINSTANTIATE_GL,a,instance);a.PointerValue=nullptr;entry(FF_DEINITIALISE,a,nullptr);dlclose(lib);[[NSFileManager defaultManager]removeItemAtPath:dir error:nil];CGLSetCurrentContext(nullptr);CGLDestroyContext(ctx);
}}
