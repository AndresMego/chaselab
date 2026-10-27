// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
#pragma once
#include <random>
#include <vector>
#include <algorithm>
#include <numeric>
#include <cmath>
#include <cstdint>
struct RandomEngine {
 struct Voice{std::vector<int>rows;double time,interval;};
 std::mt19937_64 rng;std::vector<Voice>voices;int rowCount=0;double last=-1;uint64_t generation=0;
 explicit RandomEngine(uint64_t seed):rng(seed){}
 static int limit(int rows){return std::max(1,std::min(7,rows/2));}
 static double seconds(double speed){return 4*std::pow(1./32,std::clamp(speed,0.,1.));}
 void clear(){voices.clear();last=-1;}
 void configure(int rows){if(rows!=rowCount){rowCount=rows;clear();}}
 void trigger(double now,double interval,int maximum){
  if(rowCount<1)return;int cap=std::clamp(maximum,1,limit(rowCount));int count=std::uniform_int_distribution<int>(1,cap)(rng);
  std::vector<int>pool(rowCount);std::iota(pool.begin(),pool.end(),0);
  for(int i=0;i<count;++i){int j=std::uniform_int_distribution<int>(i,rowCount-1)(rng);std::swap(pool[i],pool[j]);}
  pool.resize(count);voices.push_back({std::move(pool),now,interval});if(voices.size()>32)voices.erase(voices.begin());last=now;++generation;
 }
 void tick(double now,double interval,int maximum,bool manual,int next){
  if(manual){for(int i=0;i<std::min(256,next);++i)trigger(now,interval,maximum);}
  else if(last<0||now<last||now-last>interval*32){clear();trigger(now,interval,maximum);}
  else{int due=std::min(32,(int)std::floor((now-last)/interval));for(int i=0;i<due;++i)trigger(last+interval,interval,maximum);}
 }
 std::vector<float>levels(double now,const std::vector<float>&curve,int echoes,bool manual){
  std::vector<float>result(rowCount,-1);int span=manual?1:std::clamp(echoes,1,32);
  for(auto&voice:voices){double phase=(now-voice.time)/(voice.interval*span);if(phase<0||phase>=1)continue;double x=phase*1024;int i=std::min(1023,(int)x);float level=curve[i]+(curve[i+1]-curve[i])*(x-i);for(int r:voice.rows)result[r]=std::max(result[r],level);}
  return result;
 }
};
