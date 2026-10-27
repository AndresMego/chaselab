// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
#pragma once
#include <vector>
#include <string>
#include <cmath>
#include <algorithm>
struct BumperTiming {
    struct Voice {int step;double time;};
    std::string sequenceID;int count=0,cursor=-1;bool blastWasHeld=false;
    double lastActivity=-1,lastBlast=0;
    std::vector<Voice> voices;
    static double fadeSeconds(double speed){return 4*std::pow(1.0/32,std::clamp(speed,0.0,1.0));}
    static double blastHz(double speed){return 2*std::pow(16.0,std::clamp(speed,0.0,1.0));}
    void clear(){cursor=-1;voices.clear();lastActivity=-1;blastWasHeld=false;lastBlast=0;}
    void configure(const std::string& id,int steps){if(sequenceID!=id || count!=steps){sequenceID=id;count=steps;clear();}}
    void idle(double now,bool autoReset,double delay){if(autoReset && lastActivity>=0 && now-lastActivity>=delay && !blastWasHeld)cursor=-1;}
    void trigger(int direction,double now){
        if(count<1)return;
        cursor=cursor<0?(direction>0?0:count-1):(cursor+direction+count)%count;
        auto it=std::find_if(voices.begin(),voices.end(),[&](const Voice& v){return v.step==cursor;});
        if(it==voices.end())voices.push_back({cursor,now});else it->time=now;
        lastActivity=now;
    }
    void tick(double now,bool held,double speed,bool autoReset,double delay){
        idle(now,autoReset,delay);
        if(held){
            const double interval=1/blastHz(speed);
            if(!blastWasHeld){trigger(1,now);lastBlast=now;}
            else {
                const double elapsed=std::max(0.0,now-lastBlast);int due=(int)std::min(32.0,std::floor(elapsed/interval));
                if(elapsed>1)lastBlast=now-due*interval;
                for(int i=0;i<due;++i){lastBlast+=interval;trigger(1,lastBlast);}
            }
        }
        blastWasHeld=held;
    }
    void prune(double now,double seconds){voices.erase(std::remove_if(voices.begin(),voices.end(),[&](const Voice& v){return now-v.time>=seconds;}),voices.end());}
};
