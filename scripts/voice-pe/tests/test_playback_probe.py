"""Compile actual feed_speaker_ against mocks; not an ESP32 integration test."""
import os
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
s = (root / "components/voice_broker/voice_broker.cpp").read_text()
method = s[s.index("void VoiceBroker::feed_speaker_() {"):s.index("// -- producers", s.index("void VoiceBroker::feed_speaker_() {"))]
harness = r"""
#include <cassert>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <algorithm>
std::vector<std::string> logs;
template<class... T> void snapshot(const char *f, T... args){char b[512];std::snprintf(b,sizeof(b),f,args...);logs.emplace_back(b);}
#define ESP_LOGI(tag,fmt,...) snapshot(fmt,__VA_ARGS__)
const char *TAG="probe";
constexpr size_t SPEAKER_WRITE_BYTES=4096;
namespace protocol { constexpr uint32_t SPEAKER_RATE=24000; }
namespace audio {
struct AudioStreamInfo {uint8_t b,c;uint32_t r;AudioStreamInfo(uint8_t b,uint8_t c,uint32_t r):b(b),c(c),r(r){}
uint32_t get_sample_rate()const{return r;}uint8_t get_bits_per_sample()const{return b;}uint8_t get_channels()const{return c;}};
}
struct Speaker {bool stopped=true,running=false;size_t accept=4096; audio::AudioStreamInfo info{16,1,16000};
bool is_stopped(){return stopped;}bool is_running(){return running;}auto &get_audio_stream_info(){return info;}
void set_audio_stream_info(audio::AudioStreamInfo i){info=i;}void start(){stopped=false;running=true;}
size_t play(const uint8_t *,size_t n,int){return std::min(n,accept);}};
struct Buffer {size_t available(){return 0;}size_t read(uint8_t *,size_t,int){return 0;}};
class VoiceBroker {public: Speaker s;Buffer b;Speaker *speaker_=&s;Buffer *playback_=&b;
std::vector<uint8_t> play_holdover_{1,2,3,4};size_t play_holdover_offset_=0;
bool probe_feed_logged_=false,probe_write_logged_=false;void feed_speaker_();};
"""
cases = r"""
int main(){
 {logs.clear();VoiceBroker v;v.feed_speaker_();assert(v.s.info.r==24000);assert(logs.size()==2);
 assert(logs[0].find("input_hz=16000")!=std::string::npos);assert(logs[1].find("input_hz=24000")!=std::string::npos);}
 {logs.clear();VoiceBroker v;v.s.stopped=false;v.s.running=true;v.feed_speaker_();assert(v.s.info.r==16000);
 assert(logs[1].find("input_hz=16000")!=std::string::npos);assert(logs[1].find("requested_hz=24000")!=std::string::npos);}
 {logs.clear();VoiceBroker v;v.s.stopped=false;v.s.running=true;v.s.info.r=24000;v.feed_speaker_();assert(logs.size()==2);assert(v.s.info.r==24000);}
 {logs.clear();VoiceBroker v;v.s.accept=0;v.feed_speaker_();assert(logs.size()==1);assert(!v.probe_write_logged_);
 v.s.accept=4;v.feed_speaker_();assert(logs.size()==2);assert(v.probe_write_logged_);v.feed_speaker_();assert(logs.size()==2);}
}
"""
with tempfile.TemporaryDirectory() as d:
 p = Path(d)/"probe.cpp"
 p.write_text(harness+method+cases)
 exe = Path(d)/"probe"
 subprocess.run([os.environ.get("CXX","g++"),"-std=c++17",str(p),"-o",str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
print("4 actual-method cases passed: stopped/running16k/running24k/zero-write; metadata only")
