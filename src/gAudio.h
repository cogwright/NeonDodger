#ifndef GAUDIO_H_
#define GAUDIO_H_

#include <memory>
#include <string>
#include <vector>

#include "gSound.h"

// All of the game's sound in one place.
//
// A gSound is a single voice: starting it again while it is still running does
// not restart it, so a gun firing every 140 ms would drop most of its shots.
// Every effect therefore owns a small pool of voices and play() hands out the
// next free one. Effects loaded from several files spread those files across
// their voices, so repeated fire cycles through the variants instead of
// repeating one sample.
class gAudio {
public:
	enum Effect {
		SFX_SHOOT,
		SFX_HIT,
		SFX_EXPLODE,
		SFX_DEATH,
		SFX_START,
		SFX_COUNT
	};

	gAudio();

	void setup();
	void play(Effect effect);
	void startMusic();

	void setMuted(bool muted);
	bool isMuted() const;

private:
	struct Pool {
		std::vector<std::unique_ptr<gSound>> voices;
		int next;
		Pool() : next(0) {}
	};

	// Voices are heap allocated because gSound wraps an ma_sound, which the
	// audio engine keeps pointers to and which therefore must not move.
	void loadEffect(Effect effect, const std::vector<std::string>& files, int voicecount, float volume);

	Pool pools[SFX_COUNT];
	gSound music;
	float musicvolume;
	bool muted;
};

#endif /* GAUDIO_H_ */
