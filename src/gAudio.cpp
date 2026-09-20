#include "gAudio.h"

// Mix levels, chosen against each other rather than per file: shooting is
// constant and sits low, an explosion has to cut through it.
static const float MUSIC_VOLUME = 0.30f;

gAudio::gAudio() {
	musicvolume = MUSIC_VOLUME;
	muted = false;
}

void gAudio::setup() {
	loadEffect(SFX_SHOOT, {"shoot1.wav", "shoot2.wav", "shoot3.wav"}, 6, 0.22f);
	loadEffect(SFX_HIT, {"hit1.wav", "hit2.wav"}, 4, 0.30f);
	loadEffect(SFX_EXPLODE, {"explode.wav"}, 4, 0.45f);
	loadEffect(SFX_DEATH, {"death.wav"}, 1, 0.70f);
	loadEffect(SFX_START, {"start.wav"}, 1, 0.50f);

	if (music.loadSound("music.wav")) {
		music.setLoopType(gBaseSound::LOOPTYPE_NORMAL);
		music.setVolume(musicvolume);
	}
}

void gAudio::loadEffect(Effect effect, const std::vector<std::string>& files, int voicecount, float volume) {
	Pool& pool = pools[effect];
	for (int i = 0; i < voicecount; i++) {
		std::unique_ptr<gSound> voice(new gSound());
		if (!voice->loadSound(files[i % files.size()])) continue;
		voice->setVolume(volume);
		pool.voices.push_back(std::move(voice));
	}
}

void gAudio::play(Effect effect) {
	if (muted) return;

	Pool& pool = pools[effect];
	int count = (int)pool.voices.size();
	if (count == 0) return;

	for (int i = 0; i < count; i++) {
		int index = (pool.next + i) % count;
		gSound* voice = pool.voices[index].get();
		if (voice->isPlaying()) continue;
		pool.next = (index + 1) % count;
		voice->play();
		return;
	}

	// Everything is still ringing, so take the voice that started longest ago.
	gSound* voice = pool.voices[pool.next].get();
	voice->stop();
	voice->play();
	pool.next = (pool.next + 1) % count;
}

void gAudio::startMusic() {
	if (!music.isLoaded() || music.isPlaying()) return;
	music.play();
}

// Muting leaves the music running at zero volume rather than stopping it, so
// unmuting drops back into the loop instead of restarting the track.
void gAudio::setMuted(bool muted) {
	this->muted = muted;
	music.setVolume(muted ? 0.0f : musicvolume);
}

bool gAudio::isMuted() const {
	return muted;
}
