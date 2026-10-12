"""Host-test the actual firmware state-machine methods with mocked ESP32 I/O.
Run: CXX=g++ python3 scripts/voice-pe/tests/test_startup.py
This is not an ESP32 concurrency/audio integration test.
"""

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "components/voice_broker/voice_broker.cpp").read_text()
methods = source[
    source.index("void VoiceBroker::start(") : source.index(
        "void VoiceBroker::feed_speaker_()"
    )
]
# Also protect the YAML/protocol boundary; no pipeline selection may be baked in.
yaml = (ROOT / "voice-pe.yaml").read_text()
assert 'lambda: return wake_word == "Hey Jarvis";' in yaml
assert "micro_wake_word.enable_model: okay_nabu" in yaml
assert "micro_wake_word.enable_model: hey_jarvis" in yaml
assert "voice_backend" not in yaml and "pipeline_id" not in yaml
assert "on_boot:" not in yaml  # stock upstream boot must not be replaced
assert "config.disable_auto_reconnect = true;" in source
broker = (
    ROOT.parents[1] / "packages/voice-broker/src/voice_broker/conversation.py"
).read_text()
assert (
    broker.index("async with self._session.open(self):")
    < broker.index("await self.set_phase(Phase.LISTENING)")
    < broker.index("asyncio.create_task(self._device_loop()")
)
harness = r"""
#include <cassert>
#include <cstdint>
#include <functional>
#include <initializer_list>
#include <queue>
#include <string>
#include <utility>
#include <vector>
#define ESP_LOGW(...) ((void)0)
constexpr int pdTRUE = 1;
namespace protocol { const char *START="start", *STOP="stop"; }
enum class Phase { LISTENING, THINKING, REPLYING };
template<class... T> struct Trigger { int calls=0; void trigger(T...) { ++calls; } };
struct Device { int starts=0; void start(){ ++starts; } void stop(){} void reset(){} };
struct Frequency { void start(){} void stop(){} };
class VoiceBroker {
 public:
  enum class State { IDLE, CONNECTING, WAITING_READY, ACTIVE };
  struct IoItem { enum Op { OPEN, CLOSE }; };
  struct Event { enum Type { CONNECTED, DISCONNECTED, END, PHASE } type; uint32_t generation; Phase phase; };
  State state_=State::IDLE;
  uint32_t generation_=0, mic_samples_=0;
  bool streaming_=false, failed=false, queue_ok=true;
  std::string wake_word_;
  std::string token_="test-token";
  Device mic, speaker, buffer;
  Device *mic_source_=&mic, *speaker_=&speaker, *playback_=&buffer;
  std::vector<int> play_holdover_; int play_holdover_offset_=0;
  Frequency high_freq_;
  Trigger<> end_trigger_, error_trigger_;
  Trigger<std::string> phase_trigger_, startup_failure_trigger_;
  std::queue<Event> events;
  std::queue<Event> *event_queue_=&events;
  std::function<void()> timeout;
  int feeds=0, starts=0, stops=0;
  bool is_failed(){ return failed; }
  bool queue_io_(IoItem::Op){ return queue_ok; }
  void queue_control_(const char *type, std::initializer_list<std::pair<const char *, std::string>> = {}) {
    if (type==protocol::START) ++starts; else ++stops;
  }
  void set_timeout(const char *, int ms, std::function<void()> f){ assert(ms==10000); timeout=f; }
  void cancel_timeout(const char *){ timeout=nullptr; }
  void feed_speaker_(){ ++feeds; }
  void start(const std::string &);
  void stop(); void teardown_(); void startup_failure_(); void loop();
  void event(Event::Type t, Phase p=Phase::LISTENING){ events.push({t,generation_,p}); loop(); }
  void expire(){ auto f=timeout; if(f) f(); }
};
int xQueueReceive(std::queue<VoiceBroker::Event> *q, VoiceBroker::Event *e, int){
  if(q->empty()) return 0; *e=q->front(); q->pop(); return pdTRUE;
}
"""
cases = r"""
int main(){
  using V=VoiceBroker; using E=V::Event; using S=V::State;
  { V v; v.token_.clear(); v.start("Hey Jarvis"); assert(v.state_==S::IDLE && v.startup_failure_trigger_.calls==1 && v.mic.starts==0); }
  // Transport refusal, auth rejection, startup END and timeout fall back once.
  for(auto failure : {E::DISCONNECTED, E::END}) {
    for(bool connected : {false,true}) {
      V v; v.start("Hey Jarvis"); if(connected) v.event(E::CONNECTED);
      assert(!v.streaming_ && v.mic.starts==0);
      auto old=v.generation_; v.event(failure);
      assert(v.state_==S::IDLE && v.startup_failure_trigger_.calls==1);
      assert(v.error_trigger_.calls==0 && v.end_trigger_.calls==1);
      v.events.push({failure,old,Phase::LISTENING}); v.loop(); v.expire();
      assert(v.startup_failure_trigger_.calls==1);
    }
  }
  for(bool connected : {false,true}) {
    V v; v.start("Hey Jarvis"); if(connected) v.event(E::CONNECTED); v.expire();
    assert(v.startup_failure_trigger_.calls==1 && v.mic.starts==0);
  }
  // Readiness is the point of no replay; invalid early phases do not start audio.
  for(auto failure : {E::DISCONNECTED,E::END}) {
    V v; v.start("Hey Jarvis"); v.event(E::CONNECTED);
    assert(v.starts==1); v.event(E::PHASE,Phase::THINKING); assert(!v.streaming_);
    v.event(E::PHASE); assert(v.streaming_ && v.mic.starts==1 && !v.timeout);
    v.event(failure); assert(v.startup_failure_trigger_.calls==0);
  }
  // Button/wake cancellation in every stage never falls back, even on late events.
  for(int stage=0;stage<3;++stage) {
    V v; v.start("Hey Jarvis"); if(stage>0) v.event(E::CONNECTED);
    if(stage>1) v.event(E::PHASE);
    auto old=v.generation_; v.stop(); v.expire();
    v.events.push({E::DISCONNECTED,old,Phase::LISTENING}); v.loop();
    assert(v.startup_failure_trigger_.calls==0 && v.state_==S::IDLE);
  }
  // Local startup allocation/queue failure, plus a fresh wake after fallback.
  V failed; failed.failed=true; failed.start("Hey Jarvis");
  assert(failed.startup_failure_trigger_.calls==1 && failed.state_==S::IDLE);
  V full; full.queue_ok=false; full.start("Hey Jarvis");
  assert(full.startup_failure_trigger_.calls==1 && full.state_==S::IDLE);
  full.queue_ok=true; full.start("Hey Jarvis"); full.event(E::CONNECTED); full.event(E::PHASE);
  assert(full.streaming_ && full.startup_failure_trigger_.calls==1);
}
"""
with tempfile.TemporaryDirectory(prefix="voice-startup-test-") as directory:
    cpp = Path(directory) / "startup.cpp"
    binary = Path(directory) / "startup"
    cpp.write_text(harness + methods + cases)
    subprocess.run(
        [os.environ.get("CXX", "g++"), "-std=c++17", str(cpp), "-o", str(binary)],
        check=True,
    )
    subprocess.run([str(binary)], check=True)
print(
    "PASS: actual firmware startup, fallback, readiness, cancellation, stale events and no-replay cases"
)
