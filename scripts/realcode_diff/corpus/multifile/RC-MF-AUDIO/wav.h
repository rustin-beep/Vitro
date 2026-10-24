#ifndef WAV_H
#define WAV_H

#include <stddef.h>

#define WAV_MAX_SAMPLES 2048
#define WAV_HEADER_SIZE 44

typedef struct {
    unsigned int sample_rate;
    unsigned int channels;
    unsigned int bits_per_sample;
    unsigned int sample_count;
    unsigned char samples[WAV_MAX_SAMPLES];
} WavData;

typedef struct {
    int peak;
    int minimum;
    int average;
    int silent_samples;
    int zero_crossings;
} WavStats;

void wav_init(WavData *wav, unsigned int sample_rate, unsigned int channels,
              unsigned int bits_per_sample);
int wav_generate_test_signal(WavData *wav, int frequency, int silence_start, int silence_length);
int wav_serialize(const WavData *wav, unsigned char *buffer, int capacity);
int wav_parse(const unsigned char *buffer, int length, WavData *wav);
int wav_apply_gain(WavData *wav, double decibels, int *clipped);
int wav_detect_silence(const WavData *wav, int threshold, int *start, int *length);
void wav_stats(const WavData *wav, WavStats *stats);
void wav_hex_dump(const unsigned char *data, int length, int max_bytes);

#endif /* WAV_H */
