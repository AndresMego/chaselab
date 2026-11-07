// SPDX-License-Identifier: Apache-2.0
#include <windows.h>
#include <FFGLSDK.h>
#include <iostream>
#include <cstring>
int wmain(int argc,wchar_t**argv){
 if(argc!=2)return 2;auto dll=LoadLibraryW(argv[1]);if(!dll){std::cerr<<"LoadLibrary failed: "<<GetLastError()<<"\n";return 1;}
 using Entry=FFMixed(__stdcall*)(FFUInt32,FFMixed,FFInstanceID);
 auto entry=reinterpret_cast<Entry>(GetProcAddress(dll,"plugMain"));if(!entry){FreeLibrary(dll);return 1;}FFMixed input{};
 auto result=entry(FF_GETINFO,input,nullptr);auto info=static_cast<PluginInfoStruct*>(result.PointerValue);
 bool valid=info&&std::memcmp(info->PluginUniqueID,"CW01",4)==0&&entry(FF_GETNUMPARAMETERS,input,nullptr).UIntValue==1;
 std::cout<<(valid?"PASS Windows DLL entry point, ID and parameter ABI":"FAIL plugin ABI")<<"\n";FreeLibrary(dll);return valid?0:1;
}
