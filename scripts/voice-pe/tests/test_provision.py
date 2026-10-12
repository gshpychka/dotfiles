"""Host-test the actual credential action using dummy API/NVS objects."""

import os
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "components/voice_broker/voice_broker.cpp").read_text()
method = source[
    source.index("void VoiceBroker::provision_token(") : source.index(
        "void VoiceBroker::setup()"
    )
]
harness = r"""
#include <cassert>
#include <cstring>
#include <mutex>
#include <string>
#define ESP_LOGW(...) ((void)0)
struct Noise { bool keyed=false; bool has_psk(){return keyed;} };
struct Api { Noise noise; Noise &get_noise_ctx(){return noise;} } server;
namespace api { Api *global_api_server=&server; }
struct Preferences { bool ok=true; bool sync(){return ok;} } preferences;
Preferences *global_preferences=&preferences;
struct Pref { bool ok=true; std::string stored; int writes=0; template<class T> bool save(T *p){++writes;stored=p->value;return ok;} };
class VoiceBroker { public: struct SavedToken {char value[257]{};}; Pref token_preference_; std::mutex token_mutex_; std::string token_; bool active=false; bool is_running(){return active;} void provision_token(std::string); };
"""
cases = r"""
int main(){
 VoiceBroker v;
 v.provision_token("dummy"); assert(v.token_preference_.writes==0);
 server.noise.keyed=true; v.active=true; v.provision_token("dummy"); assert(v.token_preference_.writes==0);
 v.active=false;
 for(auto token : {std::string("bad\r\nheader"), std::string("bad token"), std::string(257, 'a')}) {v.provision_token(token); assert(v.token_preference_.writes==0);}
 v.provision_token("dummy-A"); assert(v.token_=="dummy-A" && v.token_preference_.stored=="dummy-A");
 v.provision_token("dummy-B"); assert(v.token_=="dummy-B");
 v.provision_token(""); assert(v.token_.empty() && v.token_preference_.stored.empty());
 v.token_preference_.ok=false; v.provision_token("not-accepted"); assert(v.token_.empty());
 v.token_preference_.ok=true; preferences.ok=false; v.provision_token("not-accepted"); assert(v.token_.empty());
}
"""
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp)
    (path / "test.cpp").write_text(harness + method + cases)
    subprocess.run(
        [
            os.environ.get("CXX", "g++"),
            "-std=c++20",
            "-pthread",
            str(path / "test.cpp"),
            "-o",
            str(path / "test"),
        ],
        check=True,
    )
    subprocess.run([str(path / "test")], check=True)
print(
    "credential action: auth, idle-only, validation, persistence failure and clearing passed"
)
