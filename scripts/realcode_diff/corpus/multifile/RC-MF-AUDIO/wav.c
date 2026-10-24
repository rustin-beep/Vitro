#include "wav.h"
#include <stdio.h>
#include <string.h>
#include <math.h>

static void wav_put32(unsigned char *dest, unsigned long value)
{
    dest[0] = (unsigned char)(value & 0xffUL);
    dest[1] = (unsigned char)((value >> 8) & 0xffUL);
    dest[2] = (unsigned char)((value >> 16) & 0xffUL);
    dest[3] = (unsigned char)((value >> 24) & 0xffUL);
}

static void wav_put16(unsigned char *dest, unsigned int value)
{
    dest[0] = (unsigned char)(value & 0xffu);
    dest[1] = (unsigned char)((value >> 8) & 0xffu);
}

static unsigned long wav_get32(const unsigned char *src)
{
    return (unsigned long)src[0] | ((unsigned long)src[1] << 8) |
           ((unsigned long)src[2] << 16) | ((unsigned long)src[3] << 24);
}

static unsigned int wav_get16(const unsigned char *src)
{
    return (unsigned int)src[0] | ((unsigned int)src[1] << 8);
}

void wav_init(WavData *wav, unsigned int sample_rate, unsigned int channels,
              unsigned int bits_per_sample)
{
    memset(wav, 0, sizeof(WavData));
    wav->sample_rate = sample_rate;
    wav->channels = channels;
    wav->bits_per_sample = bits_per_sample;
    wav->sample_count = 0;
}

int wav_generate_test_signal(WavData *wav, int frequency, int silence_start, int silence_length)
{
    int i;
    double step;

    if (wav == NULL || wav->sample_rate == 0) {
        return -1;
    }
    if (wav->sample_count > WAV_MAX_SAMPLES) {
        return -2;
    }
    step = 2.0 * 3.14159265358979 * (double)frequency / (double)wav->sample_rate;
    for (i = 0; i < (int)wav->sample_count; i++) {
        double value = sin(step * (double)i) * 100.0;
        int sample;
        if (i >= silence_start && i < silence_start + silence_length) {
            sample = 128;
        } else {
            sample = 128 + (int)value;
            if (sample < 0) {
                sample = 0;
            }
            if (sample > 255) {
                sample = 255;
            }
        }
        wav->samples[i] = (unsigned char)sample;
    }
    return 0;
}

int wav_serialize(const WavData *wav, unsigned char *buffer, int capacity)
{
    int data_size;

    if (wav == NULL || buffer == NULL) {
        return -1;
    }
    data_size = (int)wav->sample_count;
    if (capacity < WAV_HEADER_SIZE + data_size) {
        return -2;
    }
    memcpy(buffer, "RIFF", 4);
    wav_put32(buffer + 4, (unsigned long)(WAV_HEADER_SIZE - 8 + data_size));
    memcpy(buffer + 8, "WAVE", 4);
    memcpy(buffer + 12, "fmt ", 4);
    wav_put32(buffer + 16, 16);
    wav_put16(buffer + 20, 1);
    wav_put16(buffer + 22, wav->channels);
    wav_put32(buffer + 24, wav->sample_rate);
    wav_put32(buffer + 28, wav->sample_rate * wav->channels * (wav->bits_per_sample / 8));
    wav_put16(buffer + 32, (unsigned int)(wav->channels * (wav->bits_per_sample / 8)));
    wav_put16(buffer + 34, wav->bits_per_sample);
    memcpy(buffer + 36, "data", 4);
    wav_put32(buffer + 40, (unsigned long)data_size);
    memcpy(buffer + WAV_HEADER_SIZE, wav->samples, (size_t)data_size);
    return WAV_HEADER_SIZE + data_size;
}

int wav_parse(const unsigned char *buffer, int length, WavData *wav)
{
    int data_size;

    if (buffer == NULL || wav == NULL) {
        return -1;
    }
    if (length < WAV_HEADER_SIZE) {
        return -2;
    }
    if (memcmp(buffer, "RIFF", 4) != 0 || memcmp(buffer + 8, "WAVE", 4) != 0) {
        return -3;
    }
    memset(wav, 0, sizeof(WavData));
    wav->channels = wav_get16(buffer + 22);
    wav->sample_rate = (unsigned int)wav_get32(buffer + 24);
    wav->bits_per_sample = wav_get16(buffer + 34);
    data_size = (int)wav_get32(buffer + 40);
    if (data_size > WAV_MAX_SAMPLES) {
        data_size = WAV_MAX_SAMPLES;
    }
    if (length < WAV_HEADER_SIZE + data_size) {
        return -4;
    }
    wav->sample_count = (unsigned int)data_size;
    memcpy(wav->samples, buffer + WAV_HEADER_SIZE, (size_t)data_size);
    return 0;
}

int wav_apply_gain(WavData *wav, double decibels, int *clipped)
{
    double factor;
    int i;

    if (wav == NULL) {
        return -1;
    }
    if (clipped != NULL) {
        *clipped = 0;
    }
    factor = pow(10.0, decibels / 20.0);
    for (i = 0; i < (int)wav->sample_count; i++) {
        int centred = (int)wav->samples[i] - 128;
        int scaled = (int)(centred * factor);
        int result = 128 + scaled;
        if (result > 255) {
            result = 255;
            if (clipped != NULL) {
                (*clipped)++;
            }
        }
        if (result < 0) {
            result = 0;
            if (clipped != NULL) {
                (*clipped)++;
            }
        }
        wav->samples[i] = (unsigned char)result;
    }
    return 0;
}

int wav_detect_silence(const WavData *wav, int threshold, int *start, int *length)
{
    int i;
    int first = -1;
    int last = -1;

    if (wav == NULL) {
        return -1;
    }
    for (i = 0; i < (int)wav->sample_count; i++) {
        int centred = (int)wav->samples[i] - 128;
        int absolute = centred < 0 ? -centred : centred;
        if (absolute > threshold) {
            continue;
        }
        if (first < 0) {
            first = i;
        }
        last = i;
    }
    if (start != NULL) {
        *start = first;
    }
    if (length != NULL) {
        *length = (first < 0) ? 0 : (last - first + 1);
    }
    return (first < 0) ? 0 : 1;
}

void wav_stats(const WavData *wav, WavStats *stats)
{
    int i;
    long total = 0;

    if (wav == NULL || stats == NULL) {
        return;
    }
    stats->peak = 0;
    stats->minimum = 255;
    stats->average = 0;
    stats->silent_samples = 0;
    stats->zero_crossings = 0;
    for (i = 0; i < (int)wav->sample_count; i++) {
        int value = (int)wav->samples[i];
        int centred = value - 128;
        if (value > stats->peak) {
            stats->peak = value;
        }
        if (value < stats->minimum) {
            stats->minimum = value;
        }
        if (centred == 0) {
            stats->silent_samples++;
        }
        if (i > 0) {
            int previous = (int)wav->samples[i - 1] - 128;
            if ((previous < 0 && centred > 0) || (previous > 0 && centred < 0)) {
                stats->zero_crossings++;
            }
        }
        total += centred;
    }
    if (wav->sample_count > 0) {
        stats->average = (int)(total / (long)wav->sample_count);
    }
}

void wav_hex_dump(const unsigned char *data, int length, int max_bytes)
{
    int i;
    int limit;

    if (data == NULL) {
        return;
    }
    limit = (length < max_bytes) ? length : max_bytes;
    for (i = 0; i < limit; i += 16) {
        int j;
        printf("  %04x  ", i);
        for (j = 0; j < 16; j++) {
            if (i + j < limit) {
                printf("%02x ", data[i + j]);
            } else {
                printf("   ");
            }
        }
        printf("\n");
    }
}
