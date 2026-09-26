// Python binding for WebRTC AudioProcessing (AEC3 + high-pass filter).
//
// Only the pieces the broker needs are exposed: 10 ms mono int16 frames in both
// directions, and the statistics used to judge whether the canceller has
// converged. Frames must be fed in lockstep: one reverse (far-end, what the
// device played) frame, then one capture (near-end, what the mic heard) frame
// covering the same instant.

#include <pybind11/pybind11.h>

#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>

#include "api/audio/audio_processing.h"
#include "api/scoped_refptr.h"

namespace py = pybind11;

namespace {

class EchoCanceller {
 public:
  explicit EchoCanceller(int sample_rate_hz)
      : sample_rate_hz_(sample_rate_hz),
        frame_samples_(sample_rate_hz / 100),
        stream_config_(sample_rate_hz, 1) {
    if (sample_rate_hz != 16000 && sample_rate_hz != 32000 && sample_rate_hz != 48000) {
      throw std::invalid_argument("sample_rate_hz must be 16000, 32000 or 48000");
    }
    apm_ = webrtc::AudioProcessingBuilder().Create();
    if (!apm_) {
      throw std::runtime_error("AudioProcessingBuilder().Create() returned null");
    }
    webrtc::AudioProcessing::Config config;
    config.pipeline.maximum_internal_processing_rate = sample_rate_hz;
    config.high_pass_filter.enabled = true;
    config.echo_canceller.enabled = true;
    config.echo_canceller.mobile_mode = false;
    // Noise suppression and AGC stay off: OpenAI runs its own noise reduction,
    // and gain changes would skew the barge-in VAD's notion of loudness.
    config.noise_suppression.enabled = false;
    config.gain_controller1.enabled = false;
    config.gain_controller2.enabled = false;
    apm_->ApplyConfig(config);
    apm_->Initialize();
  }

  int frame_samples() const { return frame_samples_; }

  // Far-end frame: the audio the device was playing during the matching
  // capture frame.
  void process_reverse(py::buffer frame) {
    auto info = check_frame(frame);
    auto *data = static_cast<const int16_t *>(info.ptr);
    int16_t scratch[480];
    int err = apm_->ProcessReverseStream(data, stream_config_, stream_config_, scratch);
    if (err != webrtc::AudioProcessing::kNoError) {
      throw std::runtime_error("ProcessReverseStream failed: " + std::to_string(err));
    }
  }

  // Near-end frame: returns the echo-cancelled frame as bytes.
  py::bytes process_capture(py::buffer frame) {
    auto info = check_frame(frame);
    auto *data = static_cast<const int16_t *>(info.ptr);
    std::string out(static_cast<size_t>(frame_samples_) * sizeof(int16_t), '\0');
    // Alignment is done by the broker from device timestamps, so the residual
    // delay is only the acoustic path plus DMA slack; AEC3's delay estimator
    // tracks it from there.
    apm_->set_stream_delay_ms(0);
    int err = apm_->ProcessStream(data, stream_config_, stream_config_,
                                  reinterpret_cast<int16_t *>(out.data()));
    if (err != webrtc::AudioProcessing::kNoError) {
      throw std::runtime_error("ProcessStream failed: " + std::to_string(err));
    }
    return py::bytes(out);
  }

  py::dict stats() {
    auto s = apm_->GetStatistics();
    py::dict d;
    d["echo_return_loss"] = to_py(s.echo_return_loss);
    d["echo_return_loss_enhancement"] = to_py(s.echo_return_loss_enhancement);
    d["divergent_filter_fraction"] = to_py(s.divergent_filter_fraction);
    d["delay_ms"] = to_py(s.delay_ms);
    d["residual_echo_likelihood"] = to_py(s.residual_echo_likelihood);
    return d;
  }

 private:
  py::buffer_info check_frame(py::buffer &frame) const {
    py::buffer_info info = frame.request();
    if (info.size * info.itemsize != static_cast<py::ssize_t>(frame_samples_ * sizeof(int16_t))) {
      throw std::invalid_argument("frame must be " + std::to_string(frame_samples_) +
                                  " int16 samples (10 ms at " + std::to_string(sample_rate_hz_) + " Hz)");
    }
    return info;
  }

  template <typename T>
  static py::object to_py(const std::optional<T> &v) {
    if (!v) return py::none();
    return py::cast(*v);
  }

  int sample_rate_hz_;
  int frame_samples_;
  webrtc::StreamConfig stream_config_;
  rtc::scoped_refptr<webrtc::AudioProcessing> apm_;
};

}  // namespace

PYBIND11_MODULE(_aec, m) {
  py::class_<EchoCanceller>(m, "EchoCanceller")
      .def(py::init<int>(), py::arg("sample_rate_hz"))
      .def_property_readonly("frame_samples", &EchoCanceller::frame_samples)
      .def("process_reverse", &EchoCanceller::process_reverse, py::arg("frame"))
      .def("process_capture", &EchoCanceller::process_capture, py::arg("frame"))
      .def("stats", &EchoCanceller::stats);
}
