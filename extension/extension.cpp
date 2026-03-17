#define HL_NAME(n) midisf2_##n

#include <hl.h>

#ifdef _GUID
#undef _GUID
#endif

#include <MidiFile.h>

#define TSF_IMPLEMENTATION
#include <tsf.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstring>
#include <fstream>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <type_traits>
#include <vector>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#endif

static constexpr int kSampleRate = 48000;
static constexpr int kChannels = 2;
static constexpr int kRenderChunkFrames = 512;
static constexpr int kMaxVoices = 256;
static constexpr int kTailSeconds = 8;

static int lastDecodedChannels = 0;
static int lastDecodedSampleRate = 0;
static int lastDecodedSamples = 0;
static std::string lastError;

#if defined(_WIN32)
static constexpr DWORD kSystemMidiWarmupMs = 300;
static constexpr DWORD kSystemMidiTailMs = 600;

struct SystemMidiEvent {
	DWORD timeMs = 0;
	DWORD shortMessage = 0;
};

static std::mutex systemMidiMutex;
static std::thread systemMidiThread;
static std::atomic<bool> systemMidiStopRequested = false;
static std::atomic<bool> systemMidiPlaying = false;
static HMIDIOUT systemMidiDevice = nullptr;
#endif

struct ChannelState {
	int bankMsb = 0;
	int bankLsb = 0;
	int program = 0;
	bool hasExplicitBank = false;
};

static bool parse_midi_file(const unsigned char* bytes, size_t size, smf::MidiFile& midiFile, std::string& error);

static void clear_last_error() {
	lastError.clear();
}

static void set_last_error(const char* message) {
	lastError = message ? message : "Unknown error";
}

static void set_last_error(const std::string& message) {
	lastError = message;
}

static void set_last_decoded_format(int channels, int sampleRate, int samples) {
	lastDecodedChannels = channels;
	lastDecodedSampleRate = sampleRate;
	lastDecodedSamples = samples;
}

#if defined(_WIN32)
static void clear_system_midi_state() {
	systemMidiStopRequested = false;
	systemMidiPlaying = false;
}


static void close_system_midi_device(HMIDIOUT device) {
	if (device == nullptr)
		return;

	midiOutReset(device);
	midiOutClose(device);
}

static void stop_system_midi_playback() {
	std::thread worker;
	HMIDIOUT device = nullptr;

	{
		std::lock_guard<std::mutex> lock(systemMidiMutex);
		systemMidiStopRequested = true;
		worker = std::move(systemMidiThread);
		device = systemMidiDevice;
	}

	if (worker.joinable())
		worker.join();

	{
		std::lock_guard<std::mutex> lock(systemMidiMutex);
		device = systemMidiDevice;
		systemMidiDevice = nullptr;
	}

	close_system_midi_device(device);
	clear_system_midi_state();
}

static bool read_file_bytes(const char* path, int pathSize, std::vector<unsigned char>& bytes) {
	if (path == nullptr || pathSize <= 0) {
		set_last_error("Invalid MIDI path");
		return false;
	}

	const std::string midiPath(path, static_cast<size_t>(pathSize));
	std::ifstream input(midiPath, std::ios::binary);
	if (!input.is_open()) {
		set_last_error("Failed to open MIDI file");
		return false;
	}

	input.seekg(0, std::ios::end);
	const std::streamoff size = input.tellg();
	if (size <= 0) {
		set_last_error("Failed to read MIDI file");
		return false;
	}

	input.seekg(0, std::ios::beg);
	bytes.resize(static_cast<size_t>(size));
	input.read(reinterpret_cast<char*>(bytes.data()), size);
	if (!input) {
		set_last_error("Failed to read MIDI file");
		return false;
	}

	return true;
}

static bool build_system_midi_events(const unsigned char* midiBytes, size_t midiSize, std::vector<SystemMidiEvent>& events) {
	smf::MidiFile midiFile;
	std::string midiError;
	if (!parse_midi_file(midiBytes, midiSize, midiFile, midiError)) {
		set_last_error(midiError);
		return false;
	}

	midiFile.joinTracks();
	midiFile.doTimeAnalysis();

	const smf::MidiEventList& midiEvents = midiFile[0];
	events.clear();
	events.reserve(static_cast<size_t>(midiEvents.size()));

	for (int index = 0; index < midiEvents.size(); ++index) {
		const smf::MidiEvent& event = midiEvents[index];
		if (event.empty() || event.isMetaMessage())
			continue;

		const int status = event.getCommandByte();
		if (status < 0x80 || status >= 0xF0)
			continue;

		DWORD shortMessage = static_cast<DWORD>(event.getP0() & 0xFF);
		if (event.size() > 1)
			shortMessage |= static_cast<DWORD>(event.getP1() & 0xFF) << 8;
		if (event.size() > 2)
			shortMessage |= static_cast<DWORD>(event.getP2() & 0xFF) << 16;

		double seconds = event.seconds;
		if (seconds < 0.0)
			seconds = 0.0;

		events.push_back({
			static_cast<DWORD>(seconds * 1000.0 + 0.5),
			shortMessage,
		});
	}

	return !events.empty();
}

static bool open_system_midi_device(HMIDIOUT& device) {
	device = nullptr;
	const MMRESULT result = midiOutOpen(&device, MIDI_MAPPER, 0, 0, CALLBACK_NULL);
	if (result != MMSYSERR_NOERROR) {
		set_last_error("Failed to open system MIDI device");
		return false;
	}

	return true;
}

static void system_midi_worker(HMIDIOUT device, std::vector<SystemMidiEvent> events, bool loop) {
	using clock = std::chrono::steady_clock;
	using milliseconds = std::chrono::milliseconds;

	systemMidiPlaying = true;

	while (!systemMidiStopRequested) {
		const auto startTime = clock::now() + milliseconds(kSystemMidiWarmupMs);
		while (!systemMidiStopRequested && clock::now() < startTime)
			std::this_thread::sleep_for(milliseconds(1));

		if (systemMidiStopRequested)
			break;

		for (const SystemMidiEvent& event : events) {
			const auto eventTime = startTime + milliseconds(event.timeMs);
			while (!systemMidiStopRequested && clock::now() < eventTime)
				std::this_thread::sleep_for(milliseconds(1));

			if (systemMidiStopRequested)
				break;

			midiOutShortMsg(device, event.shortMessage);
		}

		if (systemMidiStopRequested || loop)
			continue;

		const auto tailDeadline = clock::now() + milliseconds(kSystemMidiTailMs);
		while (!systemMidiStopRequested && clock::now() < tailDeadline)
			std::this_thread::sleep_for(milliseconds(1));

		break;
	}

	close_system_midi_device(device);

	{
		std::lock_guard<std::mutex> lock(systemMidiMutex);
		if (systemMidiDevice == device)
			systemMidiDevice = nullptr;
	}

	clear_last_error();
	systemMidiPlaying = false;
}

static bool play_system_midi_path(const char* path, int pathSize, bool loop) {
	stop_system_midi_playback();

	std::vector<unsigned char> midiBytes;
	if (!read_file_bytes(path, pathSize, midiBytes))
		return false;

	std::vector<SystemMidiEvent> events;
	if (!build_system_midi_events(midiBytes.data(), midiBytes.size(), events)) {
		if (lastError.empty())
			set_last_error("No playable MIDI events found");
		return false;
	}

	HMIDIOUT device = nullptr;
	if (!open_system_midi_device(device))
		return false;

	{
		std::lock_guard<std::mutex> lock(systemMidiMutex);
		systemMidiDevice = device;
		systemMidiStopRequested = false;
		systemMidiThread = std::thread(system_midi_worker, device, std::move(events), loop);
	}

	clear_last_error();
	return true;
}

static bool is_system_midi_playing_internal() {
	return systemMidiPlaying;
}
#endif

static bool has_bytes_prefix(const unsigned char* bytes, size_t size, const char* prefix, size_t prefixSize) {
	return bytes != nullptr && size >= prefixSize && std::memcmp(bytes, prefix, prefixSize) == 0;
}

static bool is_soundfont_data(const unsigned char* bytes, size_t size) {
	return has_bytes_prefix(bytes, size, "RIFF", 4) && size >= 12 && std::memcmp(bytes + 8, "sfbk", 4) == 0;
}

static bool parse_midi_file(const unsigned char* bytes, size_t size, smf::MidiFile& midiFile, std::string& error) {
	if (!has_bytes_prefix(bytes, size, "MThd", 4)) {
		error = "Invalid MIDI header";
		return false;
	}

	std::string inputData(reinterpret_cast<const char*>(bytes), size);
	std::istringstream input(inputData, std::ios::binary);
	if (!midiFile.readSmf(input) || !midiFile.status()) {
		error = "Invalid or unsupported MIDI file";
		return false;
	}

	return true;
}

static bool is_midi_data(const unsigned char* bytes, size_t size) {
	smf::MidiFile midiFile;
	std::string error;
	return parse_midi_file(bytes, size, midiFile, error);
}

static bool apply_channel_program(tsf* synth, int channel, const ChannelState& state) {
	if (channel == 9 && !state.hasExplicitBank)
		return tsf_channel_set_presetnumber(synth, channel, state.program, 1) != 0;

	const int bank = (state.bankMsb << 7) | state.bankLsb;
	return tsf_channel_set_bank_preset(synth, channel, bank, state.program) != 0;
}

static bool initialize_channels(tsf* synth, std::array<ChannelState, 16>& channelStates) {
	for (int channel = 0; channel < 16; ++channel) {
		channelStates[channel] = ChannelState();
		if (!apply_channel_program(synth, channel, channelStates[channel])) {
			set_last_error("Failed to initialize MIDI channel state");
			return false;
		}
	}

	return true;
}

template <typename T>
static bool append_rendered_frames(tsf* synth, std::vector<T>& pcm, size_t frameCount) {
	while (frameCount > 0) {
		const int batchFrames = static_cast<int>((std::min)(frameCount, static_cast<size_t>(kRenderChunkFrames)));
		const size_t oldSize = pcm.size();
		pcm.resize(oldSize + static_cast<size_t>(batchFrames) * kChannels);

		if constexpr (std::is_same_v<T, float>)
			tsf_render_float(synth, pcm.data() + oldSize, batchFrames, 0);
		else
			tsf_render_short(synth, pcm.data() + oldSize, batchFrames, 0);

		frameCount -= static_cast<size_t>(batchFrames);
	}

	return true;
}

static bool handle_channel_controller(tsf* synth, std::array<ChannelState, 16>& channelStates, int channel, int controller, int value) {
	ChannelState& state = channelStates[static_cast<size_t>(channel)];

	switch (controller) {
		case 0:
			state.bankMsb = value & 0x7F;
			state.hasExplicitBank = true;
			if (!apply_channel_program(synth, channel, state)) {
				set_last_error("Failed to apply MIDI bank select");
				return false;
			}
			return true;
		case 32:
			state.bankLsb = value & 0x7F;
			state.hasExplicitBank = true;
			if (!apply_channel_program(synth, channel, state)) {
				set_last_error("Failed to apply MIDI bank select");
				return false;
			}
			return true;
		default:
			if (tsf_channel_midi_control(synth, channel, controller, value) == 0) {
				set_last_error("Failed to apply MIDI controller event");
				return false;
			}
			return true;
	}
}

static bool handle_midi_event(tsf* synth, std::array<ChannelState, 16>& channelStates, const smf::MidiEvent& event) {
	if (event.empty() || event.isMetaMessage())
		return true;

	const int status = event.getCommandNibble();
	const int channel = event.getChannelNibble();
	if (channel < 0 || channel > 15)
		return true;

	switch (status) {
		case 0x80:
			tsf_channel_note_off(synth, channel, event.getKeyNumber());
			return true;
		case 0x90: {
			const int velocity = event.getVelocity();
			if (velocity <= 0) {
				tsf_channel_note_off(synth, channel, event.getKeyNumber());
				return true;
			}

			if (tsf_channel_note_on(synth, channel, event.getKeyNumber(), velocity / 127.0f) == 0) {
				set_last_error("Failed to start MIDI note");
				return false;
			}
			return true;
		}
		case 0xB0:
			return handle_channel_controller(synth, channelStates, channel, event.getControllerNumber(), event.getControllerValue());
		case 0xC0: {
			ChannelState& state = channelStates[static_cast<size_t>(channel)];
			state.program = event.getP1() & 0x7F;
			if (!apply_channel_program(synth, channel, state)) {
				set_last_error("Failed to apply MIDI program change");
				return false;
			}
			return true;
		}
		case 0xE0: {
			const int pitchWheel = (event.getP2() << 7) | event.getP1();
			if (tsf_channel_set_pitchwheel(synth, channel, pitchWheel) == 0) {
				set_last_error("Failed to apply MIDI pitch bend");
				return false;
			}
			return true;
		}
		default:
			return true;
	}
}

template <typename T>
static vbyte* copy_samples(const std::vector<T>& samples, int channels, int sampleRate) {
	const int frameCount = static_cast<int>(samples.size() / (channels > 0 ? channels : 1));
	const int byteCount = static_cast<int>(samples.size() * sizeof(T));
	vbyte* result = hl_copy_bytes(reinterpret_cast<const vbyte*>(samples.data()), byteCount);

	if (result == nullptr) {
		set_last_error("Out of memory");
		return nullptr;
	}

	set_last_decoded_format(channels, sampleRate, frameCount);
	clear_last_error();
	return result;
}

template <typename T>
static vbyte* decode_midi(const unsigned char* midiBytes, int midiSize, const unsigned char* soundFontBytes, int soundFontSize) {
	if (midiBytes == nullptr || midiSize <= 0) {
		set_last_error("Invalid MIDI data");
		return nullptr;
	}

	if (soundFontBytes == nullptr || soundFontSize <= 0) {
		set_last_error("Invalid SoundFont data");
		return nullptr;
	}

	smf::MidiFile midiFile;
	std::string midiError;
	if (!parse_midi_file(midiBytes, static_cast<size_t>(midiSize), midiFile, midiError)) {
		set_last_error(midiError);
		return nullptr;
	}

	if (!is_soundfont_data(soundFontBytes, static_cast<size_t>(soundFontSize))) {
		set_last_error("Invalid SoundFont header");
		return nullptr;
	}

	tsf* synth = tsf_load_memory(soundFontBytes, soundFontSize);
	if (synth == nullptr) {
		set_last_error("Failed to load SoundFont");
		return nullptr;
	}

	tsf_set_output(synth, TSF_STEREO_INTERLEAVED, kSampleRate, 0.0f);
	if (tsf_set_max_voices(synth, kMaxVoices) == 0) {
		tsf_close(synth);
		set_last_error("Failed to allocate TinySoundFont voices");
		return nullptr;
	}

	std::array<ChannelState, 16> channelStates;
	if (!initialize_channels(synth, channelStates)) {
		tsf_close(synth);
		return nullptr;
	}

	midiFile.joinTracks();
	midiFile.doTimeAnalysis();

	std::vector<T> pcm;
	const smf::MidiEventList& events = midiFile[0];
	if (events.size() > 0) {
		double lastEventSeconds = events[events.size() - 1].seconds;
		if (lastEventSeconds < 0.0)
			lastEventSeconds = 0.0;

		const size_t estimatedFrames = static_cast<size_t>((lastEventSeconds + static_cast<double>(kTailSeconds)) * static_cast<double>(kSampleRate) + 0.5);
		pcm.reserve(estimatedFrames * static_cast<size_t>(kChannels));
	}

	size_t renderedFrames = 0;

	for (int index = 0; index < events.size(); ++index) {
		const smf::MidiEvent& event = events[index];
		double eventSeconds = event.seconds;
		if (eventSeconds < 0.0)
			eventSeconds = 0.0;

		size_t targetFrames = static_cast<size_t>(eventSeconds * static_cast<double>(kSampleRate) + 0.5);
		if (targetFrames < renderedFrames)
			targetFrames = renderedFrames;

		if (targetFrames > renderedFrames) {
			append_rendered_frames(synth, pcm, targetFrames - renderedFrames);
			renderedFrames = targetFrames;
		}

		if (!handle_midi_event(synth, channelStates, event)) {
			tsf_close(synth);
			return nullptr;
		}
	}

	int remainingTailFrames = kSampleRate * kTailSeconds;
	while (remainingTailFrames > 0 && tsf_active_voice_count(synth) > 0) {
		const int batchFrames = (std::min)(remainingTailFrames, kRenderChunkFrames);
		append_rendered_frames(synth, pcm, static_cast<size_t>(batchFrames));
		renderedFrames += static_cast<size_t>(batchFrames);
		remainingTailFrames -= batchFrames;
	}

	tsf_close(synth);

	if (pcm.empty()) {
		set_last_error("No PCM data decoded");
		return nullptr;
	}

	return copy_samples(pcm, kChannels, kSampleRate);
}

HL_PRIM bool HL_NAME(probe_midi)(vbyte* bytes, int size) {
	if (bytes == nullptr || size <= 0)
		return false;

	return is_midi_data(reinterpret_cast<const unsigned char*>(bytes), static_cast<size_t>(size));
}

HL_PRIM bool HL_NAME(probe_soundfont)(vbyte* bytes, int size) {
	if (bytes == nullptr || size <= 0)
		return false;

	return is_soundfont_data(reinterpret_cast<const unsigned char*>(bytes), static_cast<size_t>(size));
}

HL_PRIM vbyte* HL_NAME(decode_pcm_float)(vbyte* midiBytes, int midiSize, vbyte* soundFontBytes, int soundFontSize) {
	return decode_midi<float>(reinterpret_cast<const unsigned char*>(midiBytes), midiSize, reinterpret_cast<const unsigned char*>(soundFontBytes), soundFontSize);
}

HL_PRIM vbyte* HL_NAME(decode_pcm_s16)(vbyte* midiBytes, int midiSize, vbyte* soundFontBytes, int soundFontSize) {
	return decode_midi<int16_t>(reinterpret_cast<const unsigned char*>(midiBytes), midiSize, reinterpret_cast<const unsigned char*>(soundFontBytes), soundFontSize);
}

HL_PRIM int HL_NAME(decoded_channels)() {
	return lastDecodedChannels;
}

HL_PRIM int HL_NAME(decoded_sample_rate)() {
	return lastDecodedSampleRate;
}

HL_PRIM int HL_NAME(decoded_samples)() {
	return lastDecodedSamples;
}

HL_PRIM vbyte* HL_NAME(describe_last_error)() {
	return hl_copy_bytes(reinterpret_cast<const vbyte*>(lastError.c_str()), static_cast<int>(lastError.size() + 1));
}

HL_PRIM bool HL_NAME(system_midi_available)() {
	#if defined(_WIN32)
	return true;
	#else
	return false;
	#endif
}

HL_PRIM bool HL_NAME(play_system_midi)(vbyte* pathBytes, int pathSize, bool loop) {
	#if defined(_WIN32)
	return play_system_midi_path(reinterpret_cast<const char*>(pathBytes), pathSize, loop);
	#else
	(void)pathBytes;
	(void)pathSize;
	(void)loop;
	set_last_error("System MIDI playback is only available on Windows");
	return false;
	#endif
}

HL_PRIM void HL_NAME(stop_system_midi)() {
	#if defined(_WIN32)
	stop_system_midi_playback();
	clear_last_error();
	#endif
}

HL_PRIM bool HL_NAME(is_system_midi_playing)() {
	#if defined(_WIN32)
	return is_system_midi_playing_internal();
	#else
	return false;
	#endif
}

DEFINE_PRIM(_BOOL,	probe_midi,				_BYTES	_I32);
DEFINE_PRIM(_BOOL,	probe_soundfont,		_BYTES	_I32);
DEFINE_PRIM(_BYTES, decode_pcm_float,		_BYTES	_I32 _BYTES _I32);
DEFINE_PRIM(_BYTES, decode_pcm_s16,			_BYTES	_I32 _BYTES _I32);
DEFINE_PRIM(_I32,	decoded_channels,		_NO_ARG);
DEFINE_PRIM(_I32,	decoded_sample_rate,	_NO_ARG);
DEFINE_PRIM(_I32,	decoded_samples,		_NO_ARG);
DEFINE_PRIM(_BYTES, describe_last_error,	_NO_ARG);
DEFINE_PRIM(_BOOL,	system_midi_available,	_NO_ARG);
DEFINE_PRIM(_BOOL,	play_system_midi,		_BYTES	_I32 _BOOL);
DEFINE_PRIM(_VOID,	stop_system_midi,		_NO_ARG);
DEFINE_PRIM(_BOOL,	is_system_midi_playing, _NO_ARG);
