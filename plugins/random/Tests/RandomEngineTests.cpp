// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
#include "../FFGL/RandomEngine.h"
#include <iostream>
#include <set>
#include <cstdlib>
static void check(bool v,const char*m){if(!v){std::cerr<<"FAIL: "<<m<<"\n";exit(1);}}
int main(){
 RandomEngine e(12345);e.configure(14);std::set<int>seen,counts;for(int i=0;i<2000;++i){e.trigger(i,.5,7);auto&r=e.voices.back().rows;check(r.size()>=1&&r.size()<=7,"selection size");check(std::set<int>(r.begin(),r.end()).size()==r.size(),"no duplicate slice in selection");for(auto x:r){check(x>=0&&x<14,"row bounds");seen.insert(x);}counts.insert((int)r.size());check(e.voices.size()<=32,"bounded voices");}check(seen.size()==14&&counts.size()==7,"all rows and count sizes reachable");
 e.configure(3);for(int i=0;i<100;++i){e.trigger(i,1,7);check(e.voices.back().rows.size()==1,"half-row cap for odd count");}e.configure(1);e.trigger(0,1,7);check(e.voices.back().rows==std::vector<int>{0},"single slice supported");
 std::vector<float>fade(1025);for(int i=0;i<=1024;++i)fade[i]=1-i/1024.f;
 e.clear();e.trigger(0,1,1);check(std::abs(e.levels(.5,fade,0,false)[0]-.5)<.001,"fade curve phase");check(e.levels(1.5,fade,0,false)[0]<0,"base lifetime expired");check(std::abs(e.levels(1.5,fade,4,false)[0]-.625)<.001,"echo extends lifetime");check(e.levels(1.5,fade,4,true)[0]<0,"manual ignores echoes");
 e.clear();auto before=e.generation;e.tick(0,.5,1,false,0);e.tick(.49,.5,1,false,0);check(e.generation==before+1,"automatic interval");e.tick(1.1,.5,1,false,0);check(e.generation==before+3,"catch up due selections");e.tick(100,.5,1,false,0);check(e.generation==before+4&&e.voices.size()==1,"long pause does not burst");e.clear();before=e.generation;e.tick(0,1,1,true,0);check(e.voices.empty(),"manual waits for Next");e.tick(0,1,1,true,5);check(e.generation==before+5,"manual repeated triggers");
 std::cout<<"PASS: selection bounds/count distribution, no duplicates, half-row cap, single slice, bounded history, fade and echoes, automatic clock and pause handling, manual triggers\n";
}
