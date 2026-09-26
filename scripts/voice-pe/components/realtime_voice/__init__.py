import esphome.codegen as cg
from esphome import automation
from esphome.automation import maybe_simple_id
from esphome.components import esp32, microphone, speaker
import esphome.config_validation as cv
from esphome.const import CONF_ID, CONF_MICROPHONE, CONF_SPEAKER, CONF_URL

DEPENDENCIES = ["esp32", "microphone", "speaker"]
AUTO_LOAD = ["audio", "json", "ring_buffer"]

CONF_TOKEN = "token"
CONF_WAKE_WORD = "wake_word"
CONF_ON_PHASE = "on_phase"
CONF_ON_END = "on_end"
CONF_ON_ERROR = "on_error"

realtime_voice_ns = cg.esphome_ns.namespace("realtime_voice")
RealtimeVoice = realtime_voice_ns.class_("RealtimeVoice", cg.Component)
StartAction = realtime_voice_ns.class_("StartAction", automation.Action, cg.Parented.template(RealtimeVoice))
StopAction = realtime_voice_ns.class_("StopAction", automation.Action, cg.Parented.template(RealtimeVoice))
IsRunningCondition = realtime_voice_ns.class_(
    "IsRunningCondition", automation.Condition, cg.Parented.template(RealtimeVoice)
)

CONFIG_SCHEMA = cv.Schema(
    {
        cv.GenerateID(): cv.declare_id(RealtimeVoice),
        cv.Required(CONF_URL): cv.string_strict,
        cv.Required(CONF_TOKEN): cv.string_strict,
        # One 16-bit channel: the broker's echo canceller works on mono.
        cv.Required(CONF_MICROPHONE): microphone.microphone_source_schema(
            min_bits_per_sample=16, max_bits_per_sample=16, min_channels=1, max_channels=1
        ),
        # Must accept 24 kHz mono 16-bit (a resampler speaker does).
        cv.Required(CONF_SPEAKER): cv.use_id(speaker.Speaker),
        # `phase` is "listening", "thinking" or "replying".
        cv.Optional(CONF_ON_PHASE): automation.validate_automation(single=True),
        cv.Optional(CONF_ON_END): automation.validate_automation(single=True),
        cv.Optional(CONF_ON_ERROR): automation.validate_automation(single=True),
    }
).extend(cv.COMPONENT_SCHEMA)

FINAL_VALIDATE_SCHEMA = cv.Schema(
    {cv.Required(CONF_MICROPHONE): microphone.final_validate_microphone_source_schema("realtime_voice", 16000)},
    extra=cv.ALLOW_EXTRA,
)


async def to_code(config):
    var = cg.new_Pvariable(config[CONF_ID])
    await cg.register_component(var, config)

    esp32.add_idf_component(name="espressif/esp_websocket_client", ref="1.7.0")

    cg.add(var.set_url(config[CONF_URL]))
    cg.add(var.set_token(config[CONF_TOKEN]))
    cg.add(var.set_microphone_source(await microphone.microphone_source_to_code(config[CONF_MICROPHONE])))
    cg.add(var.set_speaker(await cg.get_variable(config[CONF_SPEAKER])))

    if CONF_ON_PHASE in config:
        await automation.build_automation(var.get_phase_trigger(), [(cg.std_string, "phase")], config[CONF_ON_PHASE])
    if CONF_ON_END in config:
        await automation.build_automation(var.get_end_trigger(), [], config[CONF_ON_END])
    if CONF_ON_ERROR in config:
        await automation.build_automation(var.get_error_trigger(), [], config[CONF_ON_ERROR])


ACTION_SCHEMA = maybe_simple_id({cv.GenerateID(): cv.use_id(RealtimeVoice)})


@automation.register_action(
    "realtime_voice.start",
    StartAction,
    cv.Schema(
        {
            cv.GenerateID(): cv.use_id(RealtimeVoice),
            cv.Optional(CONF_WAKE_WORD, default=""): cv.templatable(cv.string),
        }
    ),
    synchronous=True,
)
async def start_to_code(config, action_id, template_arg, args):
    var = cg.new_Pvariable(action_id, template_arg)
    await cg.register_parented(var, config[CONF_ID])
    wake_word = await cg.templatable(config[CONF_WAKE_WORD], args, cg.std_string)
    cg.add(var.set_wake_word(wake_word))
    return var


@automation.register_action("realtime_voice.stop", StopAction, ACTION_SCHEMA, synchronous=True)
async def stop_to_code(config, action_id, template_arg, args):
    var = cg.new_Pvariable(action_id, template_arg)
    await cg.register_parented(var, config[CONF_ID])
    return var


@automation.register_condition("realtime_voice.is_running", IsRunningCondition, ACTION_SCHEMA)
async def is_running_to_code(config, condition_id, template_arg, args):
    var = cg.new_Pvariable(condition_id, template_arg)
    await cg.register_parented(var, config[CONF_ID])
    return var
