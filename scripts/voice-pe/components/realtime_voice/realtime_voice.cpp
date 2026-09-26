#include "realtime_voice.h"
#include "protocol.h"

#include "esphome/components/audio/audio.h"
#include "esphome/components/json/json_util.h"
#include "esphome/core/log.h"

#include <esp_heap_caps.h>
#include <esp_timer.h>

#include <cstring>

namespace esphome::realtime_voice {

static const char *const TAG = "realtime_voice";

// Up to ~1 s of mic frames plus PLAYED reports and control messages.
static constexpr size_t IO_QUEUE_LENGTH = 96;
static constexpr size_t EVENT_QUEUE_LENGTH = 16;
// The broker keeps ~300 ms queued here; the rest is slack for network bursts.
static constexpr size_t PLAYBACK_BUFFER_BYTES = protocol::SPEAKER_RATE * sizeof(int16_t) * 2;
static constexpr size_t SPEAKER_WRITE_BYTES = 4096;
static constexpr uint32_t IO_TASK_STACK = 6144;
static constexpr TickType_t SEND_TIMEOUT = pdMS_TO_TICKS(100);
static constexpr TickType_t CLOSE_TIMEOUT = pdMS_TO_TICKS(500);

static uint8_t *alloc_frame(size_t len) {
  return static_cast<uint8_t *>(heap_caps_malloc(len, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
}

void RealtimeVoice::setup() {
  this->io_queue_ = xQueueCreate(IO_QUEUE_LENGTH, sizeof(IoItem));
  this->event_queue_ = xQueueCreate(EVENT_QUEUE_LENGTH, sizeof(Event));
  this->playback_ = ring_buffer::RingBuffer::create(PLAYBACK_BUFFER_BYTES);
  if (this->io_queue_ == nullptr || this->event_queue_ == nullptr || this->playback_ == nullptr ||
      xTaskCreate(RealtimeVoice::io_task_, "realtime_voice_io", IO_TASK_STACK, this, 5, nullptr) != pdPASS) {
    ESP_LOGE(TAG, "Failed to allocate queues, buffer or io task");
    this->mark_failed();
    return;
  }
  this->headers_ = "Authorization: Bearer " + this->token_ + "\r\n";
  this->mic_source_->add_data_callback([this](const std::vector<uint8_t> &data) { this->on_mic_data_(data); });
  this->speaker_->add_audio_output_callback(
      [this](uint32_t frames, int64_t timestamp_us) { this->on_audio_output_(frames, timestamp_us); });
}

void RealtimeVoice::dump_config() {
  ESP_LOGCONFIG(TAG, "Realtime voice:\n  URL: %s", this->url_.c_str());
}

// -- session state machine (main loop) ----------------------------------------

void RealtimeVoice::start(const std::string &wake_word) {
  if (this->state_ != State::IDLE)
    return;
  this->wake_word_ = wake_word;
  this->generation_++;
  this->state_ = State::CONNECTING;
  this->high_freq_.start();
  this->queue_io_(IoItem::OPEN);
}

void RealtimeVoice::stop() {
  if (this->state_ == State::IDLE)
    return;
  if (this->state_ == State::ACTIVE)
    this->queue_control_(protocol::STOP);
  this->teardown_();
}

void RealtimeVoice::teardown_() {
  this->streaming_ = false;
  this->flushing_ = false;
  this->mic_source_->stop();
  this->speaker_->stop();
  this->playback_->reset();
  this->play_holdover_.clear();
  this->play_holdover_offset_ = 0;
  // Queued after anything already pending, so a STOP goes out before the close.
  this->queue_io_(IoItem::CLOSE);
  // Events still in flight from this connection are now stale.
  this->generation_++;
  this->state_ = State::IDLE;
  this->high_freq_.stop();
  this->end_trigger_.trigger();
}

void RealtimeVoice::loop() {
  Event event;
  while (xQueueReceive(this->event_queue_, &event, 0) == pdTRUE) {
    if (event.generation != this->generation_)
      continue;
    switch (event.type) {
      case Event::CONNECTED:
        if (this->state_ != State::CONNECTING)
          break;
        this->state_ = State::ACTIVE;
        this->mic_samples_ = 0;
        this->queue_control_(protocol::START, "wake_word", this->wake_word_);
        this->streaming_ = true;
        this->mic_source_->start();
        break;
      case Event::DISCONNECTED:
        if (this->state_ == State::CONNECTING) {
          ESP_LOGW(TAG, "Could not reach the broker");
          this->error_trigger_.trigger();
        }
        this->teardown_();
        break;
      case Event::END:
        this->teardown_();
        break;
      case Event::FLUSH:
        this->flushing_ = true;
        this->playback_->reset();
        this->play_holdover_.clear();
        this->play_holdover_offset_ = 0;
        this->speaker_->stop();
        break;
      case Event::PHASE:
        switch (event.phase) {
          case Phase::LISTENING:
            this->phase_trigger_.trigger("listening");
            break;
          case Phase::THINKING:
            this->phase_trigger_.trigger("thinking");
            break;
          case Phase::REPLYING:
            this->phase_trigger_.trigger("replying");
            break;
        }
        break;
    }
  }

  if (this->state_ != State::ACTIVE)
    return;
  if (this->flushing_) {
    // Only once the speaker is really stopped can no more PLAYED reports for
    // the discarded audio arrive.
    if (this->speaker_->is_stopped()) {
      this->flushing_ = false;
      this->queue_control_(protocol::FLUSHED);
    }
    return;
  }
  this->feed_speaker_();
}

void RealtimeVoice::feed_speaker_() {
  if (this->play_holdover_.empty()) {
    // Whole samples only: a WebSocket fragment can end mid-sample.
    size_t available = this->playback_->available() & ~static_cast<size_t>(1);
    if (available == 0)
      return;
    this->play_holdover_.resize(std::min(available, SPEAKER_WRITE_BYTES));
    size_t read = this->playback_->read(this->play_holdover_.data(), this->play_holdover_.size(), 0);
    this->play_holdover_.resize(read);
    this->play_holdover_offset_ = 0;
    if (read == 0)
      return;
  }
  if (this->speaker_->is_stopped()) {
    this->speaker_->set_audio_stream_info(audio::AudioStreamInfo(16, 1, protocol::SPEAKER_RATE));
    this->speaker_->start();
  }
  if (!this->speaker_->is_running())
    return;
  size_t written = this->speaker_->play(this->play_holdover_.data() + this->play_holdover_offset_,
                                        this->play_holdover_.size() - this->play_holdover_offset_, 0);
  this->play_holdover_offset_ += written;
  if (this->play_holdover_offset_ >= this->play_holdover_.size()) {
    this->play_holdover_.clear();
    this->play_holdover_offset_ = 0;
  }
}

// -- producers (mic task, audio task, main loop) ------------------------------

bool RealtimeVoice::queue_io_(IoItem::Op op, uint8_t *data, size_t len) {
  IoItem item{op, this->generation_, data, len};
  if (xQueueSend(this->io_queue_, &item, 0) != pdTRUE) {
    free(data);
    return false;
  }
  return true;
}

void RealtimeVoice::queue_control_(const char *type, const char *key, const std::string &value) {
  std::string text = json::build_json([&](JsonObject root) {
    root["type"] = type;
    if (key != nullptr)
      root[key] = value;
  });
  uint8_t *data = alloc_frame(text.size());
  if (data == nullptr)
    return;
  std::memcpy(data, text.data(), text.size());
  if (!this->queue_io_(IoItem::TEXT, data, text.size()))
    ESP_LOGW(TAG, "io queue full, dropped control %s", type);
}

void RealtimeVoice::on_mic_data_(const std::vector<uint8_t> &data) {
  if (!this->streaming_)
    return;
  const uint32_t samples = data.size() / sizeof(int16_t);
  const uint32_t first = this->mic_samples_;
  // Samples are counted even when a frame is dropped, so the broker sees the gap.
  this->mic_samples_ += samples;
  // The callback runs right after the I2S read that produced these samples.
  const int64_t capture_us =
      esp_timer_get_time() - static_cast<int64_t>(samples) * 1000000 / protocol::MIC_RATE;

  const size_t len = protocol::MIC_HEADER_SIZE + data.size();
  uint8_t *frame = alloc_frame(len);
  if (frame == nullptr)
    return;
  frame[0] = protocol::KIND_MIC;
  protocol::put_u32(frame + 1, first);
  protocol::put_i64(frame + 5, capture_us);
  std::memcpy(frame + protocol::MIC_HEADER_SIZE, data.data(), data.size());
  this->queue_io_(IoItem::BINARY, frame, len);
}

void RealtimeVoice::on_audio_output_(uint32_t frames, int64_t timestamp_us) {
  if (!this->streaming_ || this->flushing_ || frames == 0)
    return;
  uint8_t *frame = alloc_frame(protocol::PLAYED_SIZE);
  if (frame == nullptr)
    return;
  frame[0] = protocol::KIND_PLAYED;
  protocol::put_u32(frame + 1, frames);
  protocol::put_i64(frame + 5, timestamp_us);
  if (!this->queue_io_(IoItem::BINARY, frame, protocol::PLAYED_SIZE))
    ESP_LOGW(TAG, "io queue full, dropped a PLAYED report");
}

void RealtimeVoice::post_event_(Event::Type type, uint32_t generation, Phase phase) {
  Event event{type, generation, phase};
  if (xQueueSend(this->event_queue_, &event, 0) != pdTRUE)
    ESP_LOGW(TAG, "event queue full");
}

// -- io task ------------------------------------------------------------------

void RealtimeVoice::io_task_(void *arg) {
  auto *self = static_cast<RealtimeVoice *>(arg);
  // Generation of the connection client_ belongs to; frames from other
  // conversations are dropped.
  uint32_t client_generation = 0;
  IoItem item;
  while (true) {
    if (xQueueReceive(self->io_queue_, &item, portMAX_DELAY) != pdTRUE)
      continue;
    switch (item.op) {
      case IoItem::OPEN:
        self->io_close_();
        client_generation = item.generation;
        self->io_open_(item.generation);
        break;
      case IoItem::CLOSE:
        self->io_close_();
        break;
      case IoItem::BINARY:
      case IoItem::TEXT:
        if (self->client_ != nullptr && item.generation == client_generation &&
            esp_websocket_client_is_connected(self->client_)) {
          int sent = item.op == IoItem::BINARY
                         ? esp_websocket_client_send_bin(self->client_, reinterpret_cast<const char *>(item.data),
                                                         item.len, SEND_TIMEOUT)
                         : esp_websocket_client_send_text(self->client_, reinterpret_cast<const char *>(item.data),
                                                          item.len, SEND_TIMEOUT);
          if (sent < 0)
            ESP_LOGW(TAG, "send failed");
        }
        break;
    }
    free(item.data);
  }
}

void RealtimeVoice::io_open_(uint32_t generation) {
  esp_websocket_client_config_t config = {};
  config.uri = this->url_.c_str();
  config.headers = this->headers_.c_str();
  // Assistant audio arrives in 40 ms frames (1921 bytes); fit one per event.
  config.buffer_size = 4096;
  // A dropped conversation ends; the next wake word opens a new one.
  config.disable_auto_reconnect = true;
  config.network_timeout_ms = 5000;
  config.ping_interval_sec = 5;
  config.pingpong_timeout_sec = 10;
  config.task_stack = 6144;

  this->handler_context_ = new HandlerContext{this, generation};
  this->client_ = esp_websocket_client_init(&config);
  if (this->client_ == nullptr) {
    ESP_LOGE(TAG, "esp_websocket_client_init failed");
    this->post_event_(Event::DISCONNECTED, generation);
    delete this->handler_context_;
    this->handler_context_ = nullptr;
    return;
  }
  esp_websocket_register_events(this->client_, WEBSOCKET_EVENT_ANY, RealtimeVoice::ws_event_handler_,
                                this->handler_context_);
  if (esp_websocket_client_start(this->client_) != ESP_OK) {
    ESP_LOGE(TAG, "esp_websocket_client_start failed");
    this->post_event_(Event::DISCONNECTED, generation);
    this->io_close_();
  }
}

void RealtimeVoice::io_close_() {
  if (this->client_ == nullptr)
    return;
  if (esp_websocket_client_is_connected(this->client_))
    esp_websocket_client_close(this->client_, CLOSE_TIMEOUT);
  esp_websocket_client_destroy(this->client_);
  this->client_ = nullptr;
  // Destroy has stopped the client's task, so the handler can't run anymore.
  delete this->handler_context_;
  this->handler_context_ = nullptr;
}

// -- ws task ------------------------------------------------------------------

void RealtimeVoice::ws_event_handler_(void *arg, esp_event_base_t base, int32_t event_id, void *event_data) {
  auto *context = static_cast<HandlerContext *>(arg);
  auto *self = context->parent;
  switch (event_id) {
    case WEBSOCKET_EVENT_CONNECTED:
      self->post_event_(Event::CONNECTED, context->generation);
      break;
    case WEBSOCKET_EVENT_DISCONNECTED:
    case WEBSOCKET_EVENT_CLOSED:
    case WEBSOCKET_EVENT_ERROR:
      self->post_event_(Event::DISCONNECTED, context->generation);
      break;
    case WEBSOCKET_EVENT_DATA:
      self->on_ws_data_(context->generation, static_cast<esp_websocket_event_data_t *>(event_data));
      break;
    default:
      break;
  }
}

void RealtimeVoice::on_ws_data_(uint32_t generation, const esp_websocket_event_data_t *data) {
  if (generation != this->generation_)
    return;
  // One WebSocket frame can arrive in several events when it exceeds
  // buffer_size; payload_offset > 0 marks the continuation pieces.
  const auto *bytes = reinterpret_cast<const uint8_t *>(data->data_ptr);
  size_t len = data->data_len;
  if (data->payload_offset == 0) {
    if (data->op_code == WS_TRANSPORT_OPCODES_BINARY) {
      this->frame_is_text_ = false;
      this->frame_kind_ = len > 0 ? bytes[0] : 0;
      bytes += 1;
      len = len > 0 ? len - 1 : 0;
    } else if (data->op_code == WS_TRANSPORT_OPCODES_TEXT) {
      this->frame_is_text_ = true;
      this->text_frame_.clear();
    } else {
      return;  // ping, pong, close: handled by the client
    }
  }

  if (this->frame_is_text_) {
    this->text_frame_.append(reinterpret_cast<const char *>(bytes), len);
    if (data->payload_offset + data->data_len >= data->payload_len)
      this->on_control_(generation, this->text_frame_);
    return;
  }
  if (this->frame_kind_ == protocol::KIND_AUDIO && len > 0) {
    if (this->playback_->write_without_replacement(bytes, len, 0) < len)
      ESP_LOGW(TAG, "playback buffer full, dropped audio");
  }
}

void RealtimeVoice::on_control_(uint32_t generation, const std::string &text) {
  json::parse_json(text, [&](JsonObject root) -> bool {
    const char *type = root["type"];
    if (type == nullptr)
      return false;
    if (std::strcmp(type, protocol::FLUSH) == 0) {
      this->post_event_(Event::FLUSH, generation);
    } else if (std::strcmp(type, protocol::END) == 0) {
      this->post_event_(Event::END, generation);
    } else if (std::strcmp(type, protocol::PHASE) == 0) {
      const char *phase = root["phase"];
      if (phase == nullptr)
        return false;
      if (std::strcmp(phase, "listening") == 0) {
        this->post_event_(Event::PHASE, generation, Phase::LISTENING);
      } else if (std::strcmp(phase, "thinking") == 0) {
        this->post_event_(Event::PHASE, generation, Phase::THINKING);
      } else if (std::strcmp(phase, "replying") == 0) {
        this->post_event_(Event::PHASE, generation, Phase::REPLYING);
      }
    } else {
      ESP_LOGW(TAG, "Unknown control message: %s", type);
    }
    return true;
  });
}

}  // namespace esphome::realtime_voice
